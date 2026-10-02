'use strict';

const SUPABASE_URL='https://pfyvsweuvdnpmvabfflh.supabase.co';
const SUPABASE_KEY='sb_publishable_FJ9hNx9T4-sNV6Ypv94vJA_cCq5TxUp';
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const isoDate=value=>value?new Date(value).toLocaleString('ja-JP',{year:'numeric',month:'long',day:'numeric',weekday:'short',hour:'2-digit',minute:'2-digit',timeZone:'Asia/Tokyo'}):'';

module.exports=async(req,res)=>{
  const id=String(req.query?.id||'');
  if(!/^[0-9a-f-]{36}$/i.test(id)){res.statusCode=400;res.setHeader('content-type','text/plain; charset=utf-8');res.end('公演IDが正しくありません。');return}
  const query=new URL(SUPABASE_URL+'/rest/v1/otaku_events');
  query.searchParams.set('select','id,title,venue,prefecture,city,starts_at,ends_at');
  query.searchParams.set('id','eq.'+id);query.searchParams.set('publication_status','eq.published');query.searchParams.set('limit','1');
  const response=await fetch(query,{headers:{apikey:SUPABASE_KEY,Authorization:'Bearer '+SUPABASE_KEY}});
  if(!response.ok){res.statusCode=502;res.setHeader('content-type','text/plain; charset=utf-8');res.end('公演情報を取得できませんでした。');return}
  const rows=await response.json();const event=rows[0];
  if(!event){res.statusCode=404;res.setHeader('content-type','text/plain; charset=utf-8');res.end('公演が見つかりません。');return}
  const origin='https://'+(req.headers.host||'otaku-live-mvp.vercel.app');const detailUrl=origin+'/event.html?id='+encodeURIComponent(event.id);
  const title=event.title+' | OTAKU LIVE';const description=isoDate(event.starts_at)+' · '+event.venue+(event.prefecture||event.city?' · '+(event.prefecture||'')+' '+(event.city||''):'');
  res.statusCode=200;res.setHeader('content-type','text/html; charset=utf-8');res.setHeader('cache-control','public, s-maxage=300, stale-while-revalidate=3600');
  res.end('<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+esc(title)+'</title><meta name="description" content="'+esc(description)+'"><link rel="canonical" href="'+esc(detailUrl)+'"><meta property="og:type" content="website"><meta property="og:site_name" content="OTAKU LIVE"><meta property="og:title" content="'+esc(title)+'"><meta property="og:description" content="'+esc(description)+'"><meta property="og:url" content="'+esc(detailUrl)+'"><meta property="og:image" content="'+esc(origin)+'/og-default.svg"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="'+esc(title)+'"><meta name="twitter:description" content="'+esc(description)+'"><meta name="twitter:image" content="'+esc(origin)+'/og-default.svg"><style>body{margin:0;background:#0b0b10;color:#f7f7fb;font-family:system-ui,sans-serif}.wrap{max-width:680px;margin:auto;padding:28px 18px}.card{background:#15151d;border:1px solid #343042;border-radius:20px;padding:22px}h1{font-size:24px;line-height:1.35}p{color:#b9bbc7;line-height:1.7}.btn{display:inline-block;background:linear-gradient(135deg,#8b5cf6,#ec4899);color:#fff;text-decoration:none;border-radius:14px;padding:13px 18px;font-weight:800}</style></head><body><main class="wrap"><section class="card"><p>OTAKU LIVE 公演情報</p><h1>'+esc(event.title)+'</h1><p>'+esc(description)+'</p><a class="btn" href="'+esc(detailUrl)+'">公演詳細を見る</a></section></main></body></html>');
};
