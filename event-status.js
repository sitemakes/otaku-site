'use strict';
(async()=>{
  const id=new URLSearchParams(location.search).get('id');
  if(!id)return;
  const {data,error}=await otakuSupabase.from('otaku_events').select('event_status,status_note,status_updated_at').eq('id',id).eq('publication_status','published').maybeSingle();
  if(error||!data||data.event_status==='scheduled')return;
  const labels={changed:'公演情報が変更されています',postponed:'公演は延期されています',cancelled:'公演は中止されています'};
  const box=document.createElement('section');box.className='card';box.setAttribute('role','status');
  const heading=document.createElement('h2');heading.textContent=labels[data.event_status]||'公演情報が更新されています';
  const note=document.createElement('p');note.textContent=data.status_note||'最新情報は公式出典をご確認ください。';
  box.append(heading,note);
  if(data.status_updated_at){const date=document.createElement('p');date.className='notice';date.textContent='更新日: '+new Date(data.status_updated_at).toLocaleString('ja-JP',{timeZone:'Asia/Tokyo'});box.append(date)}
  let tries=0;const insert=()=>{const anchor=document.querySelector('.hero');if(anchor){anchor.insertAdjacentElement('afterend',box);return}if(++tries<30)setTimeout(insert,100)};insert();
})();
