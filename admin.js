'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const tables = { groups: 'otaku_idol_groups', idols: 'otaku_idols', events: 'otaku_events' };
  const labels = { draft: '下書き', published: '公開', archived: '非公開・保管' };
  const keys = ['name','slug','group_id','title','venue','prefecture','city','starts_at','ends_at','event_status','status_note','source_url','source_kind','publication_status'];
  let editing = null, records = [], busy = false, generation = 0;
  function resetEditor() {
    editing = null; $('editor').reset(); $('lastChecked').textContent = '';
    $('editorTitle').textContent = '新規登録'; $('sourcePreview').hidden = true;
  }
  function sourcePreview() {
    $('sourcePreview').hidden = true;
    try { const url = OtakuCatalog.sourceUrl($('source_url').value); if (url) { $('sourcePreview').href = url; $('sourcePreview').hidden = false; } } catch {}
  }
  function edit(row) {
    editing = row;
    for (const key of keys) if ($(key)) $(key).value = ['starts_at','ends_at'].includes(key) ? OtakuCatalog.toJst(row[key]) : (row[key] || '');
    $('verified').checked = false;
    $('lastChecked').textContent = row.source_checked_at ? '前回確認: ' + new Date(row.source_checked_at).toLocaleString('ja-JP', {timeZone:'Asia/Tokyo'}) : '出典は未確認です。';
    $('editorTitle').textContent = '編集: ' + (row.name || row.title);
    $('message').textContent = ''; sourcePreview(); $('editorTitle').scrollIntoView({behavior:'smooth'});
  }
  function render() {
    const query = $('search').value.trim().toLowerCase();
    $('records').replaceChildren();
    for (const row of records.filter(r => (r.name || r.title).toLowerCase().includes(query))) {
      const item = document.createElement('div'); item.className = 'record';
      const title = document.createElement('div'); title.className = 'record-title'; title.textContent = row.name || row.title;
      const state = document.createElement('small'); state.textContent = `${row.is_demo ? 'DEMO' : '実在'} · ${labels[row.publication_status]}${row.starts_at ? ' · ' + OtakuCatalog.toJst(row.starts_at).replace('T',' ') : ''}`;
      title.append(state);
      const button = document.createElement('button'); button.type = 'button'; button.textContent = '編集'; button.disabled = busy; button.onclick = () => edit(row);
      item.append(title, button); $('records').append(item);
    }
    if (!$('records').children.length) $('records').textContent = '該当する情報はありません。';
  }
  async function load(more = false) {
    const request = ++generation;
    const offset = more ? records.length : 0;
    const { data, error } = await otakuSupabase.from(tables[$('kind').value]).select('*')
      .eq('is_demo', $('scope').value === 'demo').order('created_at', {ascending:false}).order('id').range(offset, offset + 49);
    if (request !== generation) return;
    if (error) throw error;
    records = more ? records.concat(data) : data;
    $('more').hidden = data.length < 50; render();
  }
  async function groups() {
    const all = [];
    for (let offset = 0; ; offset += 500) {
      const {data,error} = await otakuSupabase.from(tables.groups).select('id,name,publication_status')
        .eq('is_demo',$('scope').value === 'demo').order('name').order('id').range(offset,offset+499);
      if (error) throw error; all.push(...data); if (data.length < 500) break;
    }
    $('group_id').replaceChildren(new Option('グループを選択', ''));
    for (const group of all) $('group_id').add(new Option(`${group.name}（${labels[group.publication_status]}）`,group.id));
  }
  function ensureEventStatusFields() {
    if ($('eventStatusField')) return;
    const wrap = document.createElement('div'); wrap.id = 'eventStatusField';
    wrap.innerHTML = '<label for="event_status">公演の状態</label><select id="event_status"><option value="scheduled">予定どおり</option><option value="changed">内容変更</option><option value="postponed">延期</option><option value="cancelled">中止</option></select><label for="status_note">変更内容・利用者向け案内（状態変更時は必須）</label><textarea id="status_note" maxlength="1000" rows="4" style="width:100%;font:inherit;padding:12px;border:1px solid #3a3740;border-radius:10px;background:#101018;color:inherit"></textarea>';
    $('eventFields').append(wrap);
  }
  async function change() {
    if (busy) return;
    setBusy(true); resetEditor(); $('message').textContent = '';
    const kind = $('kind').value;
    if (kind === 'events') ensureEventStatusFields();
    $('nameField').hidden = kind === 'events'; $('slugField').hidden = kind !== 'groups';
    $('groupField').hidden = kind === 'groups'; $('eventFields').hidden = kind !== 'events';
    for (const key of ['name','slug','group_id','title','venue','starts_at']) $(key).required = key === 'name' ? kind !== 'events' : key === 'slug' ? kind === 'groups' : key === 'group_id' ? kind !== 'groups' : kind === 'events';
    try { await groups(); await load(); } catch (error) { $('message').textContent = OtakuCatalog.errorMessage(error); }
    finally { setBusy(false); }
  }
  function setBusy(value) {
    busy = value; $('fields').disabled = value; $('kind').disabled = value; $('scope').disabled = value; $('more').disabled = value;
    document.querySelectorAll('#records button').forEach(b => b.disabled = value);
  }
  $('editor').addEventListener('submit', async event => {
    event.preventDefault(); if (busy) return;
    $('message').textContent = '';
    try {
      const values = Object.fromEntries(keys.map(key => [key,$(key).value]));
      values.is_demo = $('scope').value === 'demo';
      // Every save invalidates prior verification unless the editor reconfirms it.
      values.source_checked_at = $('verified').checked ? new Date().toISOString() : null;
      const payload = OtakuCatalog.payload($('kind').value, values);
      if ($('kind').value === 'events' && (!editing || editing.group_id !== payload.group_id || Date.parse(editing.starts_at) !== Date.parse(payload.starts_at))) {
        setBusy(true);
        const range = OtakuCatalog.jstDayRange(payload.starts_at);
        const {data, error} = await otakuSupabase.from('otaku_events').select('id,title,venue,starts_at,publication_status,group_id,is_demo')
          .eq('group_id', payload.group_id).eq('is_demo', payload.is_demo).gte('starts_at', range.from).lt('starts_at', range.to);
        if (error) throw error;
        setBusy(false);
        const duplicates = OtakuCatalog.duplicateEvents({id: editing?.id, group_id: payload.group_id, is_demo: payload.is_demo, starts_at: payload.starts_at, venue: payload.venue}, data);
        if (duplicates.length && !confirm(['同じグループの同じ日の公演がすでに登録されています。', ...duplicates.map(duplicate => {
          const jst = OtakuCatalog.toJst(duplicate.starts_at);
          const details = [duplicate.nearTime ? '開始時刻がほぼ同じ' : '', duplicate.sameVenue ? '同じ会場' : ''].filter(Boolean);
          return `・${duplicate.title}（${jst.slice(5, 7).replace(/^0/, '')}/${jst.slice(8, 10).replace(/^0/, '')} ${jst.slice(11, 16)}、${duplicate.venue}、${labels[duplicate.publication_status]}）${details.length ? `［${details.join('・')}］` : ''}`;
        }), '二重登録でないことを確認しましたか？ OK で保存します。'].join('\n'))) return;
      }
      if (payload.publication_status === 'published' && !confirm('入力内容を公開します。出典と内容を確認しましたか？')) return;
      setBusy(true);
      let query = otakuSupabase.from(tables[$('kind').value]);
      query = editing ? query.update(payload).eq('id',editing.id).eq('revision',editing.revision) : query.insert(payload);
      const {data,error} = await query.select('id');
      if (error) throw error;
      if (data.length !== 1) throw new Error('他の画面で更新されたか、権限が変更されました。一覧を再読み込みして編集し直してください。');
      resetEditor(); await load();
      $('message').textContent = '保存しました。';
      $('auditDetails').open = false;
    } catch (error) { $('message').textContent = OtakuCatalog.errorMessage(error); }
    finally { setBusy(false); }
  });
  $('kind').onchange = change; $('scope').onchange = change;
  $('resetEditor').onclick = () => { resetEditor(); $('message').textContent = ''; };
  $('search').oninput = render; $('source_url').oninput = sourcePreview;
  $('more').onclick = async () => { setBusy(true); try { await load(true); } catch(e) { $('message').textContent = OtakuCatalog.errorMessage(e); } finally { setBusy(false); } };
  $('auditDetails').ontoggle = async () => {
    if (!$('auditDetails').open) return;
    const {data,error} = await otakuSupabase.from('otaku_catalog_audit').select('table_name,record_id,changed_at,before_data,after_data').order('id',{ascending:false}).limit(20);
    $('audit').replaceChildren();
    if (error) { $('audit').textContent = '履歴を取得できませんでした。'; return; }
    for (const row of data) {
      const details = document.createElement('details'); const summary = document.createElement('summary');
      summary.textContent = `${new Date(row.changed_at).toLocaleString('ja-JP',{timeZone:'Asia/Tokyo'})} · ${row.after_data.name || row.after_data.title}`;
      const pre = document.createElement('pre'); pre.textContent = JSON.stringify({変更前:row.before_data,変更後:row.after_data},null,2);
      details.append(summary,pre); $('audit').append(details);
    }
    if (!data.length) $('audit').textContent = '変更履歴はまだありません。';
  };
  (async () => {
    try {
      const user = await otakuGetUser();
      if (!user) { $('gate').textContent = '管理者アカウントでログインしてください。'; const a = document.createElement('a'); a.href = otakuLoginUrl(location.href); a.textContent = ' ログイン'; $('gate').append(a); return; }
      const {data,error} = await otakuSupabase.rpc('otaku_is_catalog_admin');
      if (error) throw error;
      if (!data) { $('gate').textContent = 'このアカウントには情報を管理する権限がありません。'; return; }
      $('gate').hidden = true; $('workspace').hidden = false; await change();
    } catch { $('gate').textContent = '管理者権限を確認できませんでした。ページを再読み込みしてください。'; }
  })();
})();
