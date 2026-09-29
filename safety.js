'use strict';
(() => {
  const reasons={spam:'迷惑投稿・スパム',harassment:'嫌がらせ',no_show:'約束の無断キャンセル',fraud:'詐欺・金銭トラブル',unsafe:'危険な行為',other:'その他'};
  const states={open:'受付済み',reviewing:'確認中',resolved:'対応済み',dismissed:'対応不要'};
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function errorText(error){
    const messages={report_duplicate:'同じ内容の通報を受け付けています。対応状況は安全設定から確認できます。',report_rate_limit:'通報は24時間に20件までです。時間を置いてお試しください。',report_details_required:'「その他」の場合は詳細を入力してください。',report_invalid_context:'この募集・メッセージを通報できません。画面を再読み込みしてください。',safety_post_unavailable:'募集が終了したか、利用できなくなりました。',safety_interaction_unavailable:'この相手とのやり取りは利用できません。',safety_event_unavailable:'この公演は利用できません。'};
    return messages[error?.message] || (error?.code==='23505'?'すでに登録されています。':error?.code==='42501'?'この操作は利用できません。ログイン状態や相手・募集の状態を確認してください。':'処理できませんでした。接続を確認して再度お試しください。');
  }
  async function actor(){const user=await otakuGetUser();if(!user){location.href=otakuLoginUrl(location.href);return null}if(!await otakuGetProfile(user.id)){location.href=otakuProfileUrl(location.href);return null}return user}
  async function block(target,after){
    const user=await actor();if(!user||user.id===target)return;
    if(!confirm('このユーザーをブロックします。双方の募集とDMが非表示になり、メッセージを送れなくなります。解除はマイページの安全設定からできます。'))return;
    const {error}=await otakuSupabase.from('otaku_user_blocks').insert({blocker_id:user.id,blocked_id:target});
    if(error&&error.code!=='23505'){alert(errorText(error));return}
    if(after)await after();else location.href='safety.html';
  }
  async function closePost(postId,userId,after){
    if(!confirm('この募集を終了します。新しいDMは開始できなくなります。すでに始まったDMは引き続き利用できます。'))return;
    const {data,error}=await otakuSupabase.from('otaku_companion_posts').update({status:'closed'}).eq('id',postId).eq('user_id',userId).eq('status','open').select('id');
    if(error){alert(errorText(error));return}
    if(!data?.length){alert('募集は終了済みか、更新できませんでした。');}
    if(after)await after();
  }
  async function report(target,context={}){
    const user=await actor();if(!user||user.id===target)return;
    if(document.getElementById('reportDialog'))return;
    const dialog=document.createElement('dialog');dialog.id='reportDialog';dialog.className='safety-dialog';
    dialog.innerHTML=`<form id="reportForm"><h2>ユーザーを通報</h2><p>運営が内容を確認します。相手に通報者の情報は表示されません。</p><label for="reportReason">理由</label><select id="reportReason">${Object.entries(reasons).map(([value,label])=>`<option value="${value}">${label}</option>`).join('')}</select><label for="reportDetails">詳細（1000文字まで）</label><textarea id="reportDetails" maxlength="1000" rows="5" placeholder="何があったか、具体的に教えてください。"></textarea><label class="safety-check"><input id="reportBlock" type="checkbox">通報後にこの相手をブロックする</label><p>通報された募集・選択したメッセージは、運営の確認用として保存されます。</p><div class="safety-row"><button id="reportSend" type="submit">通報を送信</button><button id="reportCancel" type="button">キャンセル</button></div><p id="reportMessage" role="status" aria-live="polite"></p></form>`;
    document.body.append(dialog);dialog.showModal();
    const $=id=>document.getElementById(id);let sending=false;
    $('reportCancel').onclick=()=>dialog.close();dialog.onclose=()=>dialog.remove();dialog.oncancel=event=>{if(sending)event.preventDefault()};
    $('reportForm').onsubmit=async event=>{
      event.preventDefault();if(sending)return;
      const details=$('reportDetails').value.trim();
      if($('reportReason').value==='other'&&!details){$('reportMessage').textContent='「その他」の場合は詳細を入力してください。';return}
      sending=true;$('reportSend').disabled=true;$('reportCancel').disabled=true;
      const {error}=await otakuSupabase.from('otaku_reports').insert({reporter_id:user.id,target_user_id:target,reason:$('reportReason').value,details:details||null,conversation_id:context.conversationId||null,companion_post_id:context.postId||null,message_id:context.messageId||null,status:'open'});
      if(error){sending=false;$('reportSend').disabled=false;$('reportCancel').disabled=false;$('reportMessage').textContent=errorText(error);return}
      const shouldBlock=$('reportBlock').checked;let blockError=null;
      if(shouldBlock){const result=await otakuSupabase.from('otaku_user_blocks').insert({blocker_id:user.id,blocked_id:target});if(result.error?.code!=='23505')blockError=result.error}
      dialog.close();alert(blockError?'通報を受け付けました。ブロックできなかったため、安全設定から再度お試しください。':'通報を受け付けました。対応状況はマイページの安全設定で確認できます。');
      if(shouldBlock&&!blockError)location.href='safety.html';
    };
  }
  const style=document.createElement('style');style.textContent='.safety-links{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}.safety-btn{background:#272332;border:1px solid #5a4a6d;border-radius:10px;padding:8px 12px;color:#eee;font:inherit;font-size:13px;cursor:pointer}.safety-btn:disabled{opacity:.5}.safety-dialog{color:#f7f7fb;background:#15151d;border:1px solid #5a4a6d;border-radius:18px;width:min(520px,calc(100% - 24px));max-height:90vh;padding:22px;overflow:auto}.safety-dialog::backdrop{background:#000a}.safety-dialog h2{margin-top:0;font-size:20px}.safety-dialog p{font-size:13px;color:#bbb;line-height:1.6}.safety-dialog label{display:block;margin:12px 0 6px}.safety-dialog select,.safety-dialog textarea{width:100%;padding:10px;font:inherit;background:#0d0d14;color:white;border:1px solid #45404f;border-radius:10px}.safety-row{display:flex;gap:10px;margin-top:16px}.safety-row button{padding:10px;border-radius:10px;background:#322346;color:#fff;border:1px solid #665377;font:inherit;cursor:pointer}.safety-check{display:flex!important;gap:8px;align-items:center}';document.head.append(style);
  window.OtakuSafety={reasons,states,esc,errorText,actor,block,closePost,report};
})();
