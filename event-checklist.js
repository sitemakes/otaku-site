'use strict';
window.OtakuChecklist={
  items:[
    ['ticket','チケット・入場情報'],
    ['id','身分証・必要な持ち物'],
    ['transport','交通・帰りの経路'],
    ['goods','グッズ・購入予定'],
    ['venue','会場・ロッカー・集合場所'],
    ['contact','同行者への連絡']
  ],
  mount({eventId,startsAt,user}){
    const target=document.getElementById('eventChecklist');if(!target)return;
    if(!user){target.innerHTML='<h2>公演前チェックリスト</h2><p class="muted">ログインすると、自分用の確認状況を保存できます。</p>';return}
    const rows=this.items.map(([key,label])=>({key,label,checked:false}));
    target.innerHTML='<h2>公演前チェックリスト</h2><p class="muted">準備できた項目にチェックを入れて、当日の忘れ物を減らしましょう。</p><div id="checklistItems"></div><p id="checklistStatus" class="notice" role="status"></p>';
    const list=target.querySelector('#checklistItems'),status=target.querySelector('#checklistStatus');
    const render=()=>{list.innerHTML=rows.map(row=>`<label style="display:flex;gap:10px;align-items:center;padding:10px 0;border-top:1px solid var(--line);cursor:pointer"><input type="checkbox" data-key="${row.key}" ${row.checked?'checked':''} style="width:18px;height:18px;accent-color:var(--accent)"><span>${row.label}</span></label>`).join('');list.querySelectorAll('input').forEach(input=>input.onchange=async()=>{const row=rows.find(item=>item.key===input.dataset.key);row.checked=input.checked;status.textContent='保存中…';const {error}=await otakuSupabase.from('otaku_event_checklist_items').upsert({event_id:eventId,user_id:user.id,item_key:row.key,checked:row.checked,updated_at:new Date().toISOString()},{onConflict:'event_id,user_id,item_key'});status.textContent=error?'保存できませんでした。もう一度お試しください。':'チェック状況を保存しました。';});};
    (async()=>{const {data,error}=await otakuSupabase.from('otaku_event_checklist_items').select('item_key,checked').eq('event_id',eventId).eq('user_id',user.id);if(!error)(data||[]).forEach(saved=>{const row=rows.find(item=>item.key===saved.item_key);if(row)row.checked=!!saved.checked});render();const start=new Date(startsAt);if(start>new Date()){const days=Math.ceil((start-new Date())/86400000);status.textContent=`公演まであと${days}日です。`;}})();
  }
};
