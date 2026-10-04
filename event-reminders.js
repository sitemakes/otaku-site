'use strict';
(()=>{
  const target=document.getElementById('eventReminders');
  if(!target)return;
  const style=document.createElement('style');style.textContent='.reminder-item{display:grid;gap:3px;padding:12px;border-radius:14px;background:#1e1e28;color:inherit;text-decoration:none}.reminder-item strong{color:#ffb4da}.reminder-item span{font-weight:700}.reminder-item small{color:#aeb0bd;font-size:12px}';document.head.append(style);
  const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
  function dayLabel(starts){const hours=(new Date(starts)-new Date())/3600000;if(hours<0||hours>24*7+12)return null;if(hours<=36)return 'まもなく開催';if(hours<=24*2)return '開催前日';return '開催7日前'}
  async function load(){
    const user=await otakuGetUser();if(!user){target.hidden=true;return}
    const [pref,favorites,attendees]=await Promise.all([otakuSupabase.from('otaku_notification_preferences').select('event_reminder_enabled').eq('user_id',user.id).maybeSingle(),otakuSupabase.from('otaku_event_favorites').select('event_id').eq('user_id',user.id),otakuSupabase.from('otaku_event_attendees').select('event_id').eq('user_id',user.id)]);
    if(pref.data?.event_reminder_enabled!==true){target.hidden=true;return}
    const ids=[...new Set([...(favorites.data||[]),...(attendees.data||[])].map(row=>row.event_id).filter(Boolean))];if(!ids.length){target.hidden=true;return}
    const events=await otakuSupabase.from('otaku_events').select('id,title,venue,starts_at').in('id',ids).eq('publication_status','published').order('starts_at').limit(20);
    const due=(events.data||[]).map(event=>({...event,label:dayLabel(event.starts_at)})).filter(event=>event.label);target.hidden=false;
    target.innerHTML=due.length?due.map(event=>`<a class="reminder-item" href="event.html?id=${encodeURIComponent(event.id)}"><strong>${esc(event.label)}</strong><span>${esc(event.title)}</span><small>${new Date(event.starts_at).toLocaleString('ja-JP',{timeZone:'Asia/Tokyo'})} · ${esc(event.venue||'')}</small></a>`).join(''):'<p class="meta">7日以内に開催されるお気に入り公演はありません。</p>';
  }
  load();
})();
