'use strict';

const SUPABASE_URL='https://pfyvsweuvdnpmvabfflh.supabase.co';
const SUPABASE_KEY='sb_publishable_FJ9hNx9T4-sNV6Ypv94vJA_cC5TxUp';
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
const date=value=>value?new Date(value).toLocaleDateString('ja-JP',{year:'numeric',month:'long',day:'numeric',weekday:'short',timeZone:'Asia/Tokyo'}):'';

module.exports=async(req,res)=>{
  const id=String(req.query?.id||'');
  if(!/^[0-9a-f-]{36}$/i.test(id)){res.statusCode=400;res.end('invalid event');return}
  const query=new URL(SUPABASE_URL+'/rest/v1/otaku_events');
  query.searchParams.set('select','title,venue,prefecture,city,starts_at,otaku_idol_groups(name)');
  query.searchParams.set('id','eq.'+id);query.searchParams.set('publication_status','eq.published');query.searchParams.set('limit','1');
  const response=await fetch(query,{headers:{apikey:SUPABASE_KEY,Authorization:'Bearer '+SUPABASE_KEY}});
  if(!response.ok){res.statusCode=502;res.end('event unavailable');return}
  const event=(await response.json())[0];if(!event){res.statusCode=404;res.end('event not found');return}
  const group=event.otaku_idol_groups?.name||'アイドル公演';
  const location=[event.venue,event.prefecture,event.city].filter(Boolean).join(' · ');
  const lines=[group,event.title,date(event.starts_at),location].filter(Boolean);
  res.statusCode=200;res.setHeader('content-type','image/svg+xml; charset=utf-8');res.setHeader('cache-control','public, s-maxage=300, stale-while-revalidate=3600');
  res.end(`<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630"><defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#21163c"/><stop offset="1" stop-color="#11111a"/></linearGradient></defs><rect width="1200" height="630" fill="url(#bg)"/><circle cx="1030" cy="80" r="240" fill="#8b5cf6" opacity=".25"/><circle cx="1090" cy="580" r="260" fill="#ec4899" opacity=".18"/><text x="80" y="105" fill="#d8c6ff" font-family="Arial,sans-serif" font-size="30" font-weight="700">OTAKU LIVE</text><text x="80" y="225" fill="#fff" font-family="Arial,sans-serif" font-size="54" font-weight="800">${esc(lines[0]||'公演情報')}</text><text x="80" y="310" fill="#fff" font-family="Arial,sans-serif" font-size="40" font-weight="700">${esc(lines[1]||'')}</text><text x="80" y="410" fill="#d9dae2" font-family="Arial,sans-serif" font-size="30">${esc(lines[2]||'')}</text><text x="80" y="470" fill="#b9bbc7" font-family="Arial,sans-serif" font-size="26">${esc(lines[3]||'')}</text><text x="80" y="565" fill="#aeb0bd" font-family="Arial,sans-serif" font-size="22">公演情報・同行募集・掲示板</text></svg>`);
};
