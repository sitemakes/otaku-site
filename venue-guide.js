'use strict';
(async()=>{
  const eventId=new URLSearchParams(location.search).get('id');
  if(!eventId)return;
  const {data:event,error:eventError}=await otakuSupabase.from('otaku_events').select('id,venue,prefecture,city').eq('id',eventId).eq('publication_status','published').maybeSingle();
  if(eventError||!event)return;
  let query=otakuSupabase.from('otaku_venue_guides').select('nearest_station,access_notes,lockers,toilets,convenience_store,meeting_spot,official_url,source_checked_at').eq('venue_name',event.venue).eq('publication_status','published');
  query=event.prefecture?query.eq('prefecture',event.prefecture):query.is('prefecture',null);
  query=event.city?query.eq('city',event.city):query.is('city',null);
  const {data:guide,error}=await query.maybeSingle();
  let tries=0;
  const insert=()=>{
    const hero=document.querySelector('.hero');
    if(!hero){if(++tries<30)setTimeout(insert,100);return}
    const card=document.createElement('section');card.className='card';
    const heading=document.createElement('h2');heading.textContent='会場ガイド';card.append(heading);
    if(error||!guide){
      const empty=document.createElement('p');empty.className='muted';empty.textContent='この会場の確認済みガイドはまだありません。会場についての情報交換は掲示板をご利用ください。';
      const board=document.createElement('a');board.className='btn secondary';board.href=`board.html?event=${encodeURIComponent(eventId)}&category=venue`;board.textContent='会場掲示板を見る';card.append(empty,board);
    }else{
      const fields=[['🚉 最寄駅',guide.nearest_station],['🚶 アクセス',guide.access_notes],['🔐 ロッカー',guide.lockers],['🚻 トイレ',guide.toilets],['🏪 周辺施設',guide.convenience_store],['📍 待ち合わせ',guide.meeting_spot]];
      for(const [label,value] of fields){if(!value)continue;const title=document.createElement('strong');title.textContent=label;title.style.display='block';title.style.marginTop='10px';const body=document.createElement('div');body.className='muted';body.textContent=value;card.append(title,body)}
      const source=document.createElement('a');source.href=guide.official_url;source.target='_blank';source.rel='noopener noreferrer';source.textContent='会場公式情報を確認 ↗';source.style.color='#ffc7e0';
      const checkedAt=new Date(guide.source_checked_at);
      const stale=Date.now()-checkedAt.getTime()>180*24*60*60*1000;
      const checked=document.createElement('p');checked.className='notice';checked.textContent=`確認日: ${checkedAt.toLocaleDateString('ja-JP',{timeZone:'Asia/Tokyo'})}。設備・利用条件は変更される場合があります。${stale?' 最新情報は公式サイトでもご確認ください。':''}`;
      const board=document.createElement('a');board.className='btn secondary';board.href=`board.html?event=${encodeURIComponent(eventId)}&category=venue`;board.textContent='会場掲示板を見る・体験談を書く';board.style.display='inline-block';board.style.marginTop='8px';card.append(source,checked,board);
    }
    hero.after(card);
  };
  insert();
})();
