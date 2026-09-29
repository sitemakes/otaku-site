'use strict';
(async()=>{
  const $=id=>document.getElementById(id),s=OtakuSafety,esc=s.esc;let rows=[],generation=0;
  const user=await otakuGetUser();if(!user){$('gate').textContent='管理者アカウントでログインしてください。';const a=document.createElement('a');a.href=otakuLoginUrl(location.href);a.textContent=' ログイン';$('gate').append(a);return}
  const {data:admin,error}=await otakuSupabase.rpc('otaku_is_catalog_admin');if(error||!admin){$('gate').textContent=error?'管理者権限を確認できませんでした。':'このアカウントには通報を管理する権限がありません。';return}
  $('gate').hidden=true;$('reportAdmin').hidden=false;
  async function load(more=false){
    const request=++generation,offset=more?rows.length:0;
    let query=otakuSupabase.from('otaku_reports').select('id,reason,details,status,created_at,revision,otaku_profiles!otaku_reports_reporter_id_fkey(display_name),otaku_report_evidence(snapshot)').order('created_at',{ascending:false}).order('id');
    if($('statusFilter').value)query=query.eq('status',$('statusFilter').value);
    const {data,error}=await query.range(offset,offset+29);if(request!==generation)return;if(error)throw error;
    rows=more?rows.concat(data):data;$('loadMore').hidden=data.length<30;render();
  }
  function render(){
    $('reports').innerHTML=rows.length?rows.map(r=>{
      const evidence=r.otaku_report_evidence?.snapshot||{};
      return `<section class="card"><div class="row"><h2>${esc(s.reasons[r.reason])}</h2><span class="badge">${esc(s.states[r.status])}</span></div><p class="muted">${new Date(r.created_at).toLocaleString('ja-JP',{timeZone:'Asia/Tokyo'})} · 通報者: ${esc(r.otaku_profiles?.display_name||'ユーザー')} · 対象: ${esc(evidence.target_name||'ユーザー')}</p><p class="body">${esc(r.details||'詳細コメントなし')}</p><details><summary>通報された内容・対応履歴</summary>${evidence.post?`<h3>募集内容</h3><p class="body">${esc(evidence.post.body)}</p>`:''}${evidence.message?`<h3>選択されたメッセージ</h3><p class="body">${esc(evidence.message.content)}</p>`:''}${!evidence.post&&!evidence.message?'<p class="muted">募集・メッセージの添付はありません。</p>':''}<div data-history="${r.id}"></div></details><div class="controls"><label for="state-${r.id}">対応状態</label><select id="state-${r.id}">${Object.entries(s.states).map(([v,label])=>`<option value="${v}" ${v===r.status?'selected':''}>${label}</option>`).join('')}</select><button data-save="${r.id}">状態を保存</button></div></section>`;
    }).join(''):'<p class="muted">該当する通報はありません。</p>';
    document.querySelectorAll('[data-save]').forEach(b=>b.onclick=async()=>{
      const row=rows.find(r=>r.id===b.dataset.save),status=$('state-'+row.id).value;
      if(status===row.status){$('message').textContent='状態は変更されていません。';return}b.disabled=true;
      const {data,error}=await otakuSupabase.from('otaku_reports').update({status}).eq('id',row.id).eq('revision',row.revision).select('id');
      if(error||!data?.length){$('message').textContent=error?s.errorText(error):'他の画面で更新されたか、権限が変更されました。再読み込みしてください。';b.disabled=false;return}
      $('message').textContent='対応状態を保存しました。';try{await load()}catch(error){$('message').textContent='保存は完了しました。一覧を更新できなかったため、再読み込みしてください。';b.disabled=false}
    });
    document.querySelectorAll('details').forEach(d=>d.ontoggle=async()=>{
      if(!d.open)return;const h=d.querySelector('[data-history]');
      const {data,error}=await otakuSupabase.from('otaku_report_actions').select('from_status,to_status,created_at').eq('report_id',h.dataset.history).order('id');
      h.textContent=error?'履歴を取得できませんでした。':data.map(a=>`${new Date(a.created_at).toLocaleString('ja-JP',{timeZone:'Asia/Tokyo'})} ${s.states[a.from_status]} → ${s.states[a.to_status]}`).join('\n')||'対応状態の変更はまだありません。';h.className='body';
    });
  }
  $('statusFilter').onchange=()=>load().catch(e=>$('message').textContent=s.errorText(e));
  $('loadMore').onclick=()=>load(true).catch(e=>$('message').textContent=s.errorText(e));
  try{await load()}catch(e){$('message').textContent=s.errorText(e)}
})();
