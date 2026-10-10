'use strict';

const SUPABASE_URL='https://pfyvsweuvdnpmvabfflh.supabase.co';
const SUPABASE_KEY='sb_publishable_FJ9hNx9T4-sNV6Ypv94vJA_cCq5TxUp';
const ORIGIN='https://otaku-live-mvp.vercel.app';
const STATIC_PATHS=['/','/boards.html','/goods.html','/terms.html','/privacy.html','/contact.html'];
const xmlEsc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
const staticUrls=()=>STATIC_PATHS.map(path=>'<url><loc>'+ORIGIN+xmlEsc(path)+'</loc></url>');
const sitemap=urls=>'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'+urls.join('\n')+'\n</urlset>\n';

module.exports=async(req,res)=>{
  const urls=staticUrls();
  try{
    const query=new URL(SUPABASE_URL+'/rest/v1/otaku_events');
    query.searchParams.set('select','id,updated_at,starts_at');
    query.searchParams.set('publication_status','eq.published');
    query.searchParams.set('is_demo','eq.false');
    query.searchParams.set('starts_at','gte.'+new Date().toISOString());
    query.searchParams.set('order','starts_at.asc');
    query.searchParams.set('limit','1000');
    const response=await fetch(query,{headers:{apikey:SUPABASE_KEY,Authorization:'Bearer '+SUPABASE_KEY}});
    if(!response.ok) throw new Error('sitemap source failed');
    const events=await response.json();
    for(const event of events){
      if(!/^[0-9a-f-]{36}$/i.test(String(event.id||''))) continue;
      const date=new Date(event.updated_at);
      const lastmod=Number.isNaN(date.getTime())?'':date.toISOString().slice(0,10);
      urls.push('<url><loc>'+ORIGIN+'/event.html?id='+xmlEsc(event.id)+'</loc>'+(lastmod?'<lastmod>'+lastmod+'</lastmod>':'')+'</url>');
    }
  }catch(_error){
    // Keep the static sitemap available when the public event source is unavailable.
  }
  res.statusCode=200;
  res.setHeader('content-type','application/xml; charset=utf-8');
  res.setHeader('cache-control','public, s-maxage=3600, stale-while-revalidate=86400');
  res.end(sitemap(urls));
};
