'use strict';
(()=>{
  const section=document.getElementById('userDiscovery'),search=document.getElementById('userDiscoverySearch'),list=document.getElementById('userDiscoveryList');
  if(!section||!search||!list)return;
  const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
  let viewer=null,profile=null,rows=[],following=new Set();
  function render(){
    const q=search.value.trim().toLowerCase();
    const visible=rows.filter(row=>row.id!==viewer?.id&&(!q||[row.display_name,row.username,row.prefecture].join(' ').toLowerCase().includes(q))).sort((a,b)=>{const ar=profile?.prefecture&&a.prefecture===profile.prefecture?1:0,br=profile?.prefecture&&b.prefecture===profile.prefecture?1:0;return br-ar||(a.display_name||a.username||'').localeCompare(b.display_name||b.username||'','ja')}).slice(0,12);
    if(!visible.length){list.innerHTML='<p class="meta">該当するユーザーがいません。</p>';return}
    list.innerHTML=visible.map(row=>{const name=esc(row.display_name||row.username||'ユーザー'),isFollowing=following.has(row.id);return `<div class="user-card"><div><a href="user.html?id=${encodeURIComponent(row.id)}"><strong>${name}</strong></a><div class="meta">@${esc(row.username||'')}${row.prefecture?` · ${esc(row.prefecture)}`:''}</div></div><button class="user-follow ${isFollowing?'on':''}" data-id="${row.id}">${isFollowing?'フォロー中':'フォローする'}</button></div>`}).join('');
    list.querySelectorAll('.user-follow').forEach(button=>button.onclick=async()=>{button.disabled=true;const id=button.dataset.id;const result=following.has(id)?await otakuSupabase.from('otaku_user_follows').delete().eq('follower_id',viewer.id).eq('followed_id',id):await otakuSupabase.from('otaku_user_follows').insert({follower_id:viewer.id,followed_id:id});if(!result.error){following.has(id)?following.delete(id):following.add(id);render()}else{button.disabled=false;alert(otakuRateLimitMessage(result.error)||'フォローできませんでした。')}});
  }
  async function load(){viewer=await otakuGetUser();if(!viewer){section.hidden=true;return}const [p,profiles,follows]=await Promise.all([otakuGetProfile(viewer.id),otakuSupabase.from('otaku_public_profiles').select('id,display_name,username,prefecture').limit(100),otakuSupabase.from('otaku_user_follows').select('followed_id').eq('follower_id',viewer.id)]);profile=p;rows=profiles.data||[];following=new Set((follows.data||[]).map(row=>row.followed_id));section.hidden=false;render()}
  search.addEventListener('input',render);load();
})();
