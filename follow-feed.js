'use strict';
(()=>{
  const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
  const feed=document.getElementById('followFeed'),list=document.getElementById('followFeedList');
  if(!feed||!list)return;
  const label={general:'総合',fan:'ファン交流',goods:'グッズ',venue:'会場',event_info:'公演情報',companion:'同行募集',seating:'座席',other:'その他'};
  const date=v=>new Date(v).toLocaleDateString('ja-JP',{month:'numeric',day:'numeric',timeZone:'Asia/Tokyo'});
  async function load(){
    const user=await otakuGetUser();
    if(!user){feed.hidden=true;return}
    const follows=await otakuSupabase.from('otaku_user_follows').select('followed_id').eq('follower_id',user.id);
    const ids=(follows.data||[]).map(row=>row.followed_id).filter(Boolean);
    if(!ids.length){feed.hidden=false;list.innerHTML='<p class="meta">フォローしたユーザーの活動がここに表示されます。<br><a href="boards.html">掲示板から気になるユーザーを探す</a></p>';return}
    const [posts,records,profiles]=await Promise.all([
      otakuSupabase.from('otaku_board_posts').select('id,user_id,title,body,category,created_at,event_id,idol_id').in('user_id',ids).order('created_at',{ascending:false}).limit(12),
      otakuSupabase.from('otaku_event_records').select('id,user_id,impression,setlist,attendance_note,updated_at,otaku_events(id,title)').in('user_id',ids).eq('visibility','public').eq('hidden',false).order('updated_at',{ascending:false}).limit(12),
      otakuSupabase.from('otaku_public_profiles').select('id,display_name,username').in('id',ids)
    ]);
    const names=Object.fromEntries((profiles.data||[]).map(p=>[p.id,p.display_name||p.username||'ユーザー']));
    const items=[];
    (posts.data||[]).forEach(p=>items.push({kind:'post',at:p.created_at,data:p}));
    (records.data||[]).forEach(r=>items.push({kind:'record',at:r.updated_at,data:r}));
    items.sort((a,b)=>new Date(b.at)-new Date(a.at));
    feed.hidden=false;
    if(!items.length){list.innerHTML='<p class="meta">フォロー中のユーザーに公開中の新しい活動はありません。</p>';return}
    list.innerHTML=items.slice(0,10).map(item=>{
      const d=item.data,name=esc(names[d.user_id]||'ユーザー');
      if(item.kind==='post'){
        const href=d.event_id?`board.html?event=${encodeURIComponent(d.event_id)}`:d.idol_id?`board.html?idol=${encodeURIComponent(d.idol_id)}`:'boards.html';
        return `<a class="feed-item" href="${href}"><strong>${name}</strong><span>が掲示板に投稿</span><b>${esc(d.title||label[d.category]||'新しい投稿')}</b><small>${date(item.at)}</small></a>`;
      }
      const parts=[d.impression,d.setlist,d.attendance_note].filter(Boolean).join(' / ');
      return `<a class="feed-item" href="event.html?id=${encodeURIComponent(d.otaku_events?.id||'')}"><strong>${name}</strong><span>が公演後の記録を更新</span><b>${esc(d.otaku_events?.title||'公演')}</b><small>${esc(parts.slice(0,80))}${parts.length>80?'…':''} · ${date(item.at)}</small></a>`;
    }).join('');
  }
  load();
})();
