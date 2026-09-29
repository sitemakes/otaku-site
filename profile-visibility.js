'use strict';
(async()=>{
  const user=await otakuGetUser();if(!user)return;
  const {data}=await otakuSupabase.from('otaku_profiles').select('show_age,show_gender,show_prefecture,show_bio,show_favorites').eq('id',user.id).maybeSingle();
  const ids=['showAge','showGender','showPrefecture','showBio','showFavorites'];const keys=['show_age','show_gender','show_prefecture','show_bio','show_favorites'];
  ids.forEach((id,i)=>{const el=document.getElementById(id);if(el)el.checked=data?data[keys[i]]!==false:true});
  let tries=0;const wrap=()=>{const button=document.getElementById('save');if(button&&typeof button.onclick==='function'){const original=button.onclick;button.onclick=async e=>{await original(e);if(!document.getElementById('msg').textContent.includes('保存できませんでした')){const payload={user_id:user.id};ids.forEach((id,i)=>payload[keys[i]]=document.getElementById(id)?.checked!==false);await otakuSupabase.from('otaku_profiles').update(payload).eq('id',user.id)}}}else if(++tries<30)setTimeout(wrap,100)};wrap();
})();
