'use strict';
(async()=>{
  const eventId=new URLSearchParams(location.search).get('id'); if(!eventId)return;
  const {data:event,error}=await otakuSupabase.from('otaku_events').select('id,group_id,otaku_idol_groups(id,name)').eq('id',eventId).eq('publication_status','published').maybeSingle();
  if(error||!event)return;
  const user=await otakuGetUser(); if(!user)return;
  let tries=0; const setup=async()=>{
    const actions=document.querySelector('.actions'); if(!actions){if(++tries<30)setTimeout(setup,100);return}
    const [eventFav,groupFav]=await Promise.all([
      otakuSupabase.from('otaku_event_favorites').select('event_id').eq('user_id',user.id).eq('event_id',eventId).maybeSingle(),
      otakuSupabase.from('otaku_group_favorites').select('group_id').eq('user_id',user.id).eq('group_id',event.group_id).maybeSingle()
    ]);
    const make=(label,active,table,column,value)=>{const b=document.createElement('button');b.className='btn secondary';b.type='button';b.textContent=active?'お気に入り済み ★':label;b.onclick=async()=>{b.disabled=true;const exists=b.textContent.includes('済み');const q=otakuSupabase.from(table);const result=exists?await q.delete().eq('user_id',user.id).eq(column,value):await q.insert({user_id:user.id,[column]:value});if(!result.error)b.textContent=exists?label:'お気に入り済み ★';else alert('お気に入りを更新できませんでした。');b.disabled=false};return b};
    actions.append(make('公演をお気に入り',!!eventFav.data,'otaku_event_favorites','event_id',eventId),make(`${event.otaku_idol_groups?.name||'グループ'}をお気に入り`,!!groupFav.data,'otaku_group_favorites','group_id',event.group_id));
  }; setup();
})();
