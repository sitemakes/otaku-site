'use strict';
(async()=>{
  const user=await otakuGetUser(); if(!user)return;
  const [events,groups]=await Promise.all([
    otakuSupabase.from('otaku_event_favorites').select('event_id,notify,created_at,otaku_events(id,title,venue,starts_at,event_status)').eq('user_id',user.id).order('created_at',{ascending:false}),
    otakuSupabase.from('otaku_group_favorites').select('group_id,notify,created_at,otaku_idol_groups(id,name)').eq('user_id',user.id).order('created_at',{ascending:false})
  ]);
  const anchor=document.getElementById('events')?.closest('.card'); if(!anchor)return;
  const section=document.createElement('section');section.className='card';
  const heading=document.createElement('h2');heading.style.fontSize='17px';heading.style.marginTop='0';heading.textContent='お気に入り';section.append(heading);
  const note=document.createElement('div');note.className='muted';note.textContent='公演やグループを保存して、ここから確認できます。';section.append(note);
  const list=document.createElement('div');list.className='favorites';
  const rows=[];(groups.data||[]).forEach(x=>{if(x.otaku_idol_groups)rows.push({type:'group',id:x.group_id,name:x.otaku_idol_groups.name,notify:x.notify})});
  (events.data||[]).forEach(x=>{if(x.otaku_events)rows.push({type:'event',id:x.event_id,name:x.otaku_events.title,sub:`${new Date(x.otaku_events.starts_at).toLocaleString('ja-JP')} · ${x.otaku_events.venue}`,notify:x.notify})});
  if(events.error||groups.error||!rows.length){const empty=document.createElement('div');empty.className='muted';empty.textContent=events.error||groups.error?'お気に入りを取得できませんでした。':'まだお気に入りはありません。';list.append(empty)}
  else rows.forEach(row=>{const item=document.createElement('div');item.className='favorite';const text=document.createElement('div');const title=document.createElement('div');title.className='fav-main';title.textContent=(row.type==='group'?'♥ ':'★ ')+row.name;text.append(title);if(row.sub){const sub=document.createElement('div');sub.className='fav-sub';sub.textContent=row.sub;text.append(sub)}const link=document.createElement('a');link.className='mini';link.href=row.type==='group'?`index.html?q=${encodeURIComponent(row.name)}`:`event.html?id=${encodeURIComponent(row.id)}`;link.textContent='開く';const label=document.createElement('label');label.className='mini';const check=document.createElement('input');check.type='checkbox';check.checked=row.notify!==false;check.setAttribute('aria-label','このお気に入りの通知');check.onchange=async()=>{const table=row.type==='group'?'otaku_group_favorites':'otaku_event_favorites';const column=row.type==='group'?'group_id':'event_id';const {error}=await otakuSupabase.from(table).update({notify:check.checked}).eq('user_id',user.id).eq(column,row.id);if(error){check.checked=!check.checked;alert('通知設定を保存できませんでした。')}};label.append(check,' 通知');item.append(text,link,label);list.append(item)});
  section.append(list);anchor.insertAdjacentElement('afterend',section);
})();
