'use strict';
window.otakuReportContent=async(kind,id)=>{
 const user=await otakuGetUser(); if(!user){location.href=otakuLoginUrl(location.href);return}
 const reason=prompt('通報理由を入力してください（1000文字以内）。通報者は相手に表示されません。');
 if(!reason?.trim())return;
 if(reason.trim().length>1000){alert('1000文字以内で入力してください。');return}
 const {error}=await otakuSupabase.from('otaku_content_reports').insert({reporter_id:user.id,kind,target_id:id,reason:reason.trim()});
 alert(error?(error.code==='23505'?'通報済みです。':'通報できませんでした。プロフィール登録と接続を確認してください。'):'通報を受け付けました。');
};
