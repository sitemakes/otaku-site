'use strict';
(async()=>{
  const eventId=new URLSearchParams(location.search).get('id');
  if(!eventId)return;
  const [eventResult,viewer]=await Promise.all([
    otakuSupabase.from('otaku_events').select('id,title,starts_at,ends_at').eq('id',eventId).eq('publication_status','published').maybeSingle(),
    otakuGetUser()
  ]);
  const event=eventResult.data;if(eventResult.error||!event)return;
  const profile=viewer?await otakuGetProfile(viewer.id):null;
  const endedAt=new Date(event.ends_at||event.starts_at),ended=endedAt<=new Date();
  let records=[];
  let authorNames={};
  const recordColumns='id,user_id,impression,setlist,attendance_note,visibility,hidden,updated_at';
  const initialRecords=await otakuSupabase.from('otaku_event_records').select(recordColumns).eq('event_id',eventId).order('updated_at',{ascending:false}).limit(50);
  records=initialRecords.data||[];
  const styleInput=element=>{element.style.cssText='width:100%;box-sizing:border-box;margin-top:5px;padding:11px;border-radius:10px;border:1px solid #45404f;background:#101018;color:#f7f7fb;font:inherit'};
  const text=value=>{const node=document.createElement('div');node.className='muted';node.style.whiteSpace='pre-wrap';node.textContent=value;return node};
  const heading=value=>{const node=document.createElement('strong');node.style.display='block';node.style.marginTop='12px';node.textContent=value;return node};
  async function load(){
    const {data,error}=await otakuSupabase.from('otaku_event_records').select(recordColumns).eq('event_id',eventId).order('updated_at',{ascending:false}).limit(50);
    if(error){list.textContent='記録を読み込めませんでした。';return}
    records=data||[];renderList();
    if(viewer&&records.length){
      const ids=[...new Set(records.map(row=>row.user_id))];
      const result=await otakuSupabase.from('otaku_public_profiles').select('id,display_name,username').in('id',ids);
      if(!result.error){authorNames=Object.fromEntries((result.data||[]).map(profile=>[profile.id,profile.display_name||profile.username]));renderList()}
    }
  }
  function renderList(){
    list.replaceChildren();
    const publicRows=records.filter(row=>!row.hidden&&(row.visibility==='public'||row.user_id===viewer?.id));
    if(!publicRows.length){list.textContent='まだ公開された記録はありません。';return}
    for(const row of publicRows){
      const item=document.createElement('article');item.className='post';
      const who=document.createElement('div');who.className='who';const author=viewer?document.createElement('a'):document.createElement('span');if(viewer)author.href=`user.html?id=${encodeURIComponent(row.user_id)}`;author.textContent=authorNames[row.user_id]||'ユーザー';who.append(author);if(row.user_id===viewer?.id&&row.visibility==='private')who.append(' · 自分だけ');item.append(who);
      if(row.impression)item.append(heading('感想'),text(row.impression));
      if(row.setlist)item.append(heading('セットリスト'),text(row.setlist));
      if(row.attendance_note)item.append(heading('参戦メモ'),text(row.attendance_note));
      const meta=document.createElement('div');meta.className='notice';meta.textContent=`更新: ${new Date(row.updated_at).toLocaleString('ja-JP',{timeZone:'Asia/Tokyo'})}`;item.append(meta);
      if(row.user_id!==viewer?.id){const report=document.createElement('button');report.type='button';report.className='safety-btn';report.textContent='通報';report.onclick=()=>otakuReportContent('event_record',row.id);item.append(report)}
      list.append(item);
    }
  }
  const card=document.createElement('section');card.className='card';const title=document.createElement('h2');title.textContent='公演後の記録';const intro=document.createElement('p');intro.className='muted';intro.textContent='感想、セットリスト、参戦メモを残せます。セットリストは公式発表や会場で確認した内容をご自身で入力してください。';const list=document.createElement('div');list.id='eventRecords';card.append(title,intro);
  if(!ended){const status=document.createElement('p');status.className='notice';status.textContent=`記録は公演終了後（${endedAt.toLocaleString('ja-JP',{timeZone:'Asia/Tokyo'})}以降）に作成できます。`;card.append(status)}
  else if(!viewer){const login=document.createElement('a');login.href=otakuLoginUrl(location.href);login.textContent='ログインして自分の記録を残す';login.className='btn secondary';card.append(login)}
  else if(!profile){const makeProfile=document.createElement('a');makeProfile.href=otakuProfileUrl(location.href);makeProfile.textContent='プロフィールを作成して記録を残す';makeProfile.className='btn secondary';card.append(makeProfile)}
  else {
    const form=document.createElement('div');form.style.marginTop='14px';const existing=records.find(row=>row.user_id===viewer.id);
    const impression=document.createElement('textarea');impression.maxLength=3000;impression.rows=4;impression.placeholder='ライブの感想';impression.value=existing?.impression||'';styleInput(impression);
    const setlist=document.createElement('textarea');setlist.maxLength=5000;setlist.rows=5;setlist.placeholder='セットリスト（任意）';setlist.value=existing?.setlist||'';styleInput(setlist);
    const note=document.createElement('textarea');note.maxLength=2000;note.rows=3;note.placeholder='参戦メモ（任意）';note.value=existing?.attendance_note||'';styleInput(note);
    const visibility=document.createElement('select');visibility.append(new Option('公開する','public'),new Option('自分だけ','private'));visibility.value=existing?.visibility||'public';styleInput(visibility);
    const save=document.createElement('button');save.type='button';save.className='btn primary';save.textContent=existing?'記録を更新する':'記録を残す';save.style.marginTop='12px';const status=document.createElement('p');status.className='notice';
    save.onclick=async()=>{const payload={impression:impression.value.trim()||null,setlist:setlist.value.trim()||null,attendance_note:note.value.trim()||null,visibility:visibility.value};if(!payload.impression&&!payload.setlist&&!payload.attendance_note){status.textContent='感想・セットリスト・参戦メモのいずれかを入力してください。';return}save.disabled=true;const record=records.find(row=>row.user_id===viewer.id);const result=record?await otakuSupabase.from('otaku_event_records').update(payload).eq('id',record.id).select('id'):await otakuSupabase.from('otaku_event_records').insert({event_id:eventId,user_id:viewer.id,...payload}).select('id');save.disabled=false;if(result.error||!result.data?.length){status.textContent='保存できませんでした。公演終了時刻と入力内容を確認してください。';return}status.textContent='保存しました。';save.textContent='記録を更新する';await load()};
    for(const [label,input] of [['感想',impression],['セットリスト',setlist],['参戦メモ',note],['公開範囲',visibility]]){const l=document.createElement('label');l.textContent=label;l.style.display='block';l.style.marginTop='10px';l.append(input);form.append(l)}form.append(save);
    if(existing){const remove=document.createElement('button');remove.type='button';remove.className='btn secondary';remove.textContent='記録を削除する';remove.style.marginTop='8px';remove.onclick=async()=>{if(!confirm('この公演後の記録を削除しますか？'))return;remove.disabled=true;const result=await otakuSupabase.from('otaku_event_records').delete().eq('id',existing.id);remove.disabled=false;if(result.error){status.textContent='削除できませんでした。';return}status.textContent='記録を削除しました。';impression.value='';setlist.value='';note.value='';visibility.value='public';save.textContent='記録を残す';await load()};form.append(remove)}
    form.append(status);card.append(form)
  }
  card.append(list);
  let tries=0;const insert=()=>{const hero=document.querySelector('.hero');if(!hero){if(++tries<50)setTimeout(insert,100);return}hero.after(card);load()};insert();
})();
