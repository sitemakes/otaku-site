'use strict';
const id=new URLSearchParams(location.search).get('id');let user=null,conversation=null,otherId=null,lastSignature=null,poll=null,loading=false,sending=false,statusNotice='';
const $=id=>document.getElementById(id),esc=OtakuSafety.esc;
function unavailable(){conversation=null;clearInterval(poll);$('messages').replaceChildren();$('chatNotice').textContent='このDMは利用できなくなりました。ブロックなどにより非表示になる場合があります。';$('safetyActions').querySelectorAll('button').forEach(b=>b.hidden=true);document.querySelector('.composer').hidden=true}
async function init(){
  if(!id){location.href='dm.html';return}user=await otakuGetUser();if(!user){location.href=otakuLoginUrl(location.href);return}
  const {data:c,error}=await otakuSupabase.from('otaku_conversations').select('id,event_id,companion_post_id,goods_post_id,owner_user_id,requester_user_id').eq('id',id).maybeSingle();
  if(error){$('chatNotice').textContent='DMを取得できませんでした。ページを再読み込みしてください。';$('send').disabled=true;return}if(!c){unavailable();return}
  conversation=c;otherId=c.owner_user_id===user.id?c.requester_user_id:c.owner_user_id;
  const [{data:p},{data:e},{data:g},{data:match},{data:companionPost}]=await Promise.all([otakuSupabase.from('otaku_profiles').select('display_name,username').eq('id',otherId).maybeSingle(),c.event_id?otakuSupabase.from('otaku_events').select('title,starts_at').eq('id',c.event_id).maybeSingle():Promise.resolve({data:null}),c.goods_post_id?otakuSupabase.from('otaku_goods_posts').select('item_name').eq('id',c.goods_post_id).maybeSingle():Promise.resolve({data:null}),c.companion_post_id?otakuSupabase.from('otaku_companion_matches').select('conversation_id').eq('conversation_id',id).maybeSingle():Promise.resolve({data:null}),c.companion_post_id?otakuSupabase.from('otaku_companion_posts').select('status,deadline_at').eq('id',c.companion_post_id).maybeSingle():Promise.resolve({data:null})]);
  $('title').textContent=p?.display_name||p?.username||'ユーザー';$('title').href='user.html?id='+encodeURIComponent(otherId);$('event').textContent=c.goods_post_id?'グッズ交換 · '+(g?.item_name||'募集'):(e?.title||'');document.title=$('title').textContent+' | OTAKU LIVE';
  $('reportUser').hidden=false;$('blockUser').hidden=false;
  if(c.companion_post_id){
    if(match){statusNotice='同行者として成立しています。';if(e?.starts_at&&new Date(e.starts_at)<new Date()){$('reviewUser').hidden=false;$('reviewUser').onclick=()=>location.href='review.html?conversation='+encodeURIComponent(id)}}
    else if(c.owner_user_id===user.id&&companionPost?.status==='open'&&(!companionPost.deadline_at||new Date(companionPost.deadline_at)>new Date())){$('matchUser').hidden=false;$('matchUser').onclick=async()=>{if(!confirm('このユーザーを同行者に決定しますか？決定後は変更できません。'))return;$('matchUser').disabled=true;const result=await otakuSupabase.from('otaku_companion_matches').insert({post_id:c.companion_post_id,conversation_id:id,owner_user_id:user.id,matched_user_id:otherId});if(result.error){$('chatNotice').textContent=result.error.code==='23505'?'この募集はすでに同行者が決定しています。':'同行者を決定できませんでした。';$('matchUser').disabled=false;return}$('matchUser').hidden=true;statusNotice='同行者として成立しました。募集は自動で終了しました。';$('chatNotice').textContent=statusNotice}}
  }
  $('reportUser').onclick=()=>OtakuSafety.report(otherId,{conversationId:id});
  $('blockUser').onclick=()=>OtakuSafety.block(otherId,()=>{unavailable();location.href='safety.html'});
  await loadMessages(true);if(conversation)poll=setInterval(()=>loadMessages(false),3000);
}
async function loadMessages(forceScroll=false){
  if(loading||!conversation)return;loading=true;
  try{
    const {data:c,error:ce}=await otakuSupabase.from('otaku_conversations').select('id').eq('id',id).maybeSingle();
    if(ce){$('chatNotice').textContent='更新を取得できません。接続を確認してください。';return}if(!c){unavailable();return}
    const {data,error}=await otakuSupabase.from('otaku_messages').select('id,sender_id,content,created_at').eq('conversation_id',id).order('created_at',{ascending:true});
    if(error){$('chatNotice').textContent='メッセージを取得できませんでした。';return}
    $('chatNotice').textContent=statusNotice;const rows=data||[],signature=rows.map(x=>x.id).join(',');if(signature===lastSignature)return;lastSignature=signature;
    $('messages').innerHTML=rows.length?rows.map(m=>`<div class="bubble ${m.sender_id===user.id?'mine':'theirs'}"><div>${esc(m.content).replace(/\n/g,'<br>')}</div><div class="time">${new Date(m.created_at).toLocaleTimeString('ja-JP',{hour:'2-digit',minute:'2-digit',timeZone:'Asia/Tokyo'})}</div>${m.sender_id!==user.id?`<button class="safety-btn" data-message-report="${m.id}">このメッセージを通報</button>`:''}</div>`).join(''):'<div class="empty">最初のメッセージを送ってみましょう。</div>';
    $('messages').querySelectorAll('[data-message-report]').forEach(b=>b.onclick=()=>OtakuSafety.report(otherId,{conversationId:id,messageId:b.dataset.messageReport}));
    if(forceScroll||rows.length)window.scrollTo({top:document.body.scrollHeight,behavior:forceScroll?'auto':'smooth'});
  }finally{loading=false}
}
async function sendMessage(){
  const content=$('input').value.trim();if(!content||!conversation||sending)return;sending=true;$('send').disabled=true;
  try{
    const {error}=await otakuSupabase.from('otaku_messages').insert({conversation_id:id,sender_id:user.id,content});
    if(error){$('chatNotice').textContent=otakuRateLimitMessage(error)||OtakuSafety.errorText(error);if(error.code==='42501')await loadMessages();return}
    $('input').value='';await loadMessages(true);
  }finally{sending=false;$('send').disabled=false}
}
$('send').onclick=sendMessage;
$('input').addEventListener('keydown',event=>{if(event.key==='Enter'&&!event.shiftKey&&!event.isComposing){event.preventDefault();sendMessage()}});
window.addEventListener('focus',()=>loadMessages());window.addEventListener('pagehide',()=>clearInterval(poll));
window.addEventListener('pageshow',event=>{if(event.persisted&&conversation){loadMessages();clearInterval(poll);poll=setInterval(()=>loadMessages(),3000)}});
init();
