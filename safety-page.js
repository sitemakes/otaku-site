'use strict';
(async()=>{
  const $=id=>document.getElementById(id),s=OtakuSafety,esc=s.esc;let user=await s.actor();if(!user)return;
  const rows={posts:[],blocks:[],reports:[]};
  async function load(kind,more=false){
    const offset=more?rows[kind].length:0;
    let query=kind==='posts'?otakuSupabase.from('otaku_companion_posts').select('id,event_id,user_id,status,body,created_at,otaku_events(title)').eq('user_id',user.id).order('created_at',{ascending:false}).order('id'):
      kind==='blocks'?otakuSupabase.from('otaku_user_blocks').select('blocked_id,created_at,otaku_profiles!otaku_user_blocks_blocked_id_fkey(display_name)').eq('blocker_id',user.id).order('created_at',{ascending:false}).order('blocked_id'):
      otakuSupabase.from('otaku_reports').select('id,target_user_id,reason,details,status,created_at,otaku_profiles!otaku_reports_target_user_id_fkey(display_name)').eq('reporter_id',user.id).order('created_at',{ascending:false}).order('id');
    const {data,error}=await query.range(offset,offset+49);if(error)throw error;
    rows[kind]=more?rows[kind].concat(data):data;$(kind+'More').hidden=data.length<50;render(kind);
  }
  function render(kind){
    const list=rows[kind],el=$(kind==='posts'?'myPosts':kind==='blocks'?'myBlocks':'myReports');
    if(!list.length){el.textContent=kind==='posts'?'まだ募集はありません。':kind==='blocks'?'ブロックしたユーザーはいません。':'通報はありません。';return}
    if(kind==='posts'){
      el.innerHTML=list.map(p=>`<div class="record"><div class="row"><a href="event.html?id=${encodeURIComponent(p.event_id)}">${esc(p.otaku_events?.title||'非公開の公演')}</a><span class="badge">${p.status==='open'?'募集中':'募集終了'}</span></div><p class="body">${esc(p.body)}</p>${p.status==='open'?`<button data-close="${p.id}">募集を終了</button>`:''}</div>`).join('');
      el.querySelectorAll('[data-close]').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await s.closePost(b.dataset.close,user.id,()=>load('posts'))}catch(error){$('pageMessage').textContent=s.errorText(error)}finally{b.disabled=false}});
    }else if(kind==='blocks'){
      el.innerHTML=list.map(b=>`<div class="record row"><span>${esc(b.otaku_profiles?.display_name||'ユーザー')}</span><button data-unblock="${b.blocked_id}">ブロック解除</button></div>`).join('');
      el.querySelectorAll('[data-unblock]').forEach(b=>b.onclick=async()=>{
        if(!confirm('このユーザーのブロックを解除しますか？'))return;b.disabled=true;
        const {error}=await otakuSupabase.from('otaku_user_blocks').delete().eq('blocker_id',user.id).eq('blocked_id',b.dataset.unblock);
        if(error){$('pageMessage').textContent=s.errorText(error);b.disabled=false;return}try{await load('blocks')}catch(error){$('pageMessage').textContent=s.errorText(error);b.disabled=false}
      });
    }else el.innerHTML=list.map(r=>`<div class="record"><div class="row"><strong>${esc(s.reasons[r.reason])}</strong><span class="badge">${esc(s.states[r.status])}</span></div><p class="muted">対象: ${esc(r.otaku_profiles?.display_name||'ユーザー')} · ${new Date(r.created_at).toLocaleString('ja-JP',{timeZone:'Asia/Tokyo'})}</p><p class="body">${esc(r.details)}</p></div>`).join('');
  }
  for(const kind of ['posts','blocks','reports'])$(kind+'More').onclick=async()=>{const b=$(kind+'More');b.disabled=true;try{await load(kind,true)}catch(error){$('pageMessage').textContent=s.errorText(error)}finally{b.disabled=false}};
  const results=await Promise.allSettled(['posts','blocks','reports'].map(k=>load(k)));
  if(results.some(r=>r.status==='rejected'))$('pageMessage').textContent='一部の情報を取得できませんでした。ページを再読み込みしてください。';
})();
