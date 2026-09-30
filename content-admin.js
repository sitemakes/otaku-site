'use strict';
(async()=>{
 const $=id=>document.getElementById(id);let offset=0,busy=false;
 const {data:admin,error}=await otakuSupabase.rpc('otaku_is_catalog_admin');
 if(error||!admin){$('message').textContent='管理者アカウントでログインしてください。';return}
 async function load(){
 const {data,error}=await otakuSupabase.from('otaku_content_reports').select('id,kind,reason,snapshot,status,created_at').order('created_at',{ascending:false}).order('id').range(offset,offset+29);
 if(error){$('message').textContent='取得できませんでした。';return}
 $('message').textContent='内容を確認し、対応理由を記録してください。';
 for(const r of data){
 const section=document.createElement('section');section.className='card';
 const kindLabel={board:'掲示板の投稿',board_reply:'掲示板の返信',goods:'グッズ交換募集',review:'評価',event_record:'公演後の記録'}[r.kind]||'投稿';
 const title=document.createElement('h2');title.textContent=kindLabel+' · '+(r.status==='open'?'受付済み':'対応済み');
 const body=document.createElement('p');body.className='body';body.textContent=r.reason+'\n\n'+(r.snapshot.body||r.snapshot.comment||r.snapshot.impression||r.snapshot.setlist||r.snapshot.attendance_note||'コメントなし');
 const reason=document.createElement('input');reason.maxLength=500;reason.placeholder='対応理由（必須）';reason.setAttribute('aria-label','対応理由');
 section.append(title,body,reason);
 for(const [action,label] of [['hide','非表示'],['restore','再公開'],['resolve','対応完了']]){
 const b=document.createElement('button');b.textContent=label;b.onclick=async()=>{
 if(busy)return;if(!reason.value.trim()){alert('理由を入力してください。');return}busy=true;b.disabled=true;
 const {error}=await otakuSupabase.rpc('otaku_moderate_content',{report:r.id,action,reason:reason.value.trim()});
 busy=false;b.disabled=false;if(error){$('message').textContent='更新できませんでした。削除済みの投稿は「対応完了」を選んでください。';return}
 $('records').replaceChildren();offset=0;await load();
 };section.append(b)}
 const details=document.createElement('details'),summary=document.createElement('summary'),history=document.createElement('p');summary.textContent='対応履歴';details.append(summary,history);details.ontoggle=async()=>{
 if(!details.open)return;
 const {data,error}=await otakuSupabase.from('otaku_content_actions').select('action,reason,created_at').eq('report_id',r.id).order('id');
 history.textContent=error?'履歴を取得できませんでした。':data.map(x=>x.created_at+' '+x.action+' '+x.reason).join('\n')||'まだ履歴はありません。';history.className='body';
 };section.append(details);$('records').append(section)
 }
 offset+=data.length;$('more').hidden=data.length<30;
 }
 $('more').onclick=load;await load();
})();
