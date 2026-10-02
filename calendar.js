'use strict';
(() => {
  const pad=value=>String(value).padStart(2,'0');
  const googleDate=value=>new Date(value).toISOString().replace(/[-:]/g,'').replace(/\.\d{3}Z$/,'Z');
  const appleDate=value=>{const d=new Date(value);return d.getFullYear()+pad(d.getMonth()+1)+pad(d.getDate())+'T'+pad(d.getHours())+pad(d.getMinutes())+pad(d.getSeconds())};
  const icsEscape=value=>String(value??'').replace(/\\/g,'\\\\').replace(/;/g,'\\;').replace(/,/g,'\\,').replace(/\r?\n/g,'\\n');
  const locationOf=event=>[event.venue,event.prefecture,event.city].filter(Boolean).join(' ');
  const detailUrl=event=>new URL('event.html?id='+encodeURIComponent(event.id),location.href).href;
  function makeIcs(event){
    const start=new Date(event.starts_at),end=new Date(event.ends_at||start.getTime()+2*60*60*1000);
    const title=event.title+' | OTAKU LIVE',description='公演詳細: '+detailUrl(event),location=locationOf(event);
    return ['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//OTAKU LIVE//JP','CALSCALE:GREGORIAN','BEGIN:VEVENT','UID:'+event.id+'@otaku-live-mvp.vercel.app','DTSTAMP:'+googleDate(new Date()),'DTSTART;TZID=Asia/Tokyo:'+appleDate(start),'DTEND;TZID=Asia/Tokyo:'+appleDate(end),'SUMMARY:'+icsEscape(title),'DESCRIPTION:'+icsEscape(description),'LOCATION:'+icsEscape(location),'URL:'+detailUrl(event),'END:VEVENT','END:VCALENDAR'].join('\r\n')+'\r\n';
  }
  function downloadIcs(event){
    const blob=new Blob([makeIcs(event)],{type:'text/calendar;charset=utf-8'});
    const link=document.createElement('a');link.href=URL.createObjectURL(blob);link.download=(event.title||'otaku-live-event').replace(/[\\/:*?"<>|]/g,'_')+'.ics';link.click();setTimeout(()=>URL.revokeObjectURL(link.href),1000);
  }
  function open(event){
    document.getElementById('calendarDialog')?.remove();
    const dialog=document.createElement('dialog');dialog.id='calendarDialog';dialog.style.cssText='color:#f7f7fb;background:#15151d;border:1px solid #5a4a6d;border-radius:18px;width:min(480px,calc(100% - 28px));padding:22px';
    const title=document.createElement('h2');title.textContent='カレンダーに追加';title.style.marginTop='0';
    const note=document.createElement('p');note.textContent='登録先を選んでください。公演終了時刻が未登録の場合は、開演から2時間後で作成します。';note.style.cssText='color:#b9bbc7;line-height:1.6;font-size:13px';
    const google=document.createElement('a');google.textContent='Googleカレンダー';google.target='_blank';google.rel='noopener noreferrer';google.className='btn primary';google.style.cssText='display:block;text-align:center;text-decoration:none;margin-top:14px';
    const start=googleDate(event.starts_at),end=googleDate(event.ends_at||new Date(new Date(event.starts_at).getTime()+2*60*60*1000));const params=new URLSearchParams({action:'TEMPLATE',text:event.title,dates:start+'/'+end,details:'OTAKU LIVE 公演詳細: '+detailUrl(event),location:locationOf(event),ctz:'Asia/Tokyo'});google.href='https://calendar.google.com/calendar/render?'+params;
    const apple=document.createElement('button');apple.type='button';apple.textContent='iPhone / Appleカレンダー';apple.className='btn secondary';apple.style.cssText='display:block;width:100%;margin-top:10px';apple.onclick=()=>downloadIcs(event);
    const close=document.createElement('button');close.type='button';close.textContent='閉じる';close.className='btn secondary';close.style.cssText='display:block;width:100%;margin-top:10px';close.onclick=()=>dialog.close();
    dialog.append(title,note,google,apple,close);document.body.append(dialog);dialog.showModal();dialog.onclose=()=>dialog.remove();
  }
  window.OtakuCalendar={open};
})();
