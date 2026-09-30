'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const params = new URLSearchParams(location.search);
  const eventId = params.get('event'), idolId = params.get('idol');
  const requestedCategory = params.get('category') || '';
  const labels = {general:'雑談・質問',fan:'ファン交流',goods:'グッズ',venue:'会場・アクセス',event_info:'公演情報',companion:'同行募集',seating:'座席・入場',other:'その他'};
  let user = null, isAdmin = false, loading = false;

  function categoryList() {
    return eventId ? ['event_info','venue','goods','companion','seating','other']
      : idolId ? ['general','fan','goods','event_info','other']
      : ['general','fan','goods','venue','other'];
  }
  function setupCategories() {
    const list = categoryList();
    $('category').replaceChildren(...list.map(value => new Option(labels[value], value)));
    $('category').value = list.includes(requestedCategory) ? requestedCategory : list[0];
  }
  function boardUrl(category) {
    const query = new URLSearchParams();
    if (eventId) query.set('event', eventId);
    if (idolId) query.set('idol', idolId);
    query.set('category', category);
    return `board.html?${query}`;
  }
  function profileName(row) {
    return row.otaku_profiles?.display_name || row.otaku_profiles?.username || 'ユーザー';
  }
  function actionButton(label, handler, danger = false) {
    const button = document.createElement('button');
    button.type = 'button'; button.textContent = label;
    if (danger) button.className = 'danger';
    button.onclick = handler; return button;
  }
  function metaLine(row, pinned = false) {
    const meta = document.createElement('div'); meta.className = 'meta';
    if (pinned) { const pin = document.createElement('span'); pin.className = 'pin'; pin.textContent = '📌 固定'; meta.append(pin); }
    meta.append(`${profileName(row)} · ${new Date(row.created_at).toLocaleString('ja-JP')}`);
    return meta;
  }
  async function removeReply(id) {
    if (!confirm('返信を削除しますか？')) return;
    const {error} = await otakuSupabase.from('otaku_board_replies').delete().eq('id', id);
    if (error) alert('返信を削除できませんでした。'); else await load();
  }
  function renderReply(reply) {
    const item = document.createElement('div'); item.className = 'reply';
    item.append(metaLine(reply), document.createTextNode(`\n${reply.body}`));
    const actions = document.createElement('div'); actions.className = 'actions';
    if (reply.user_id === user.id) actions.append(actionButton('削除', () => removeReply(reply.id), true));
    else actions.append(actionButton('通報', () => otakuReportContent('board_reply', reply.id)));
    item.append(actions); return item;
  }
  function replyComposer(postId) {
    const form = document.createElement('div'); form.className = 'reply-form'; form.hidden = true;
    const textarea = document.createElement('textarea'); textarea.maxLength = 1000; textarea.placeholder = '返信を入力（1,000文字以内）';
    const submit = actionButton('返信を投稿', async () => {
      const body = textarea.value.trim(); if (!body || loading) return;
      loading = true; submit.disabled = true;
      const {error} = await otakuSupabase.from('otaku_board_replies').insert({post_id:postId,user_id:user.id,body});
      loading = false; submit.disabled = false;
      if (error) { alert('返信を投稿できませんでした。'); return; }
      await load(); document.getElementById(`post-${postId}`)?.scrollIntoView({block:'center'});
    });
    form.append(textarea, submit); return form;
  }
  async function removePost(id) {
    if (!confirm('投稿とその返信を削除しますか？')) return;
    const {error} = await otakuSupabase.from('otaku_board_posts').delete().eq('id', id);
    if (error) alert('投稿を削除できませんでした。'); else await load();
  }
  function renderPost(post, replies) {
    const article = document.createElement('article'); article.className = 'post'; article.id = `post-${post.id}`;
    article.append(metaLine(post, post.pinned));
    const heading = document.createElement('strong'); heading.className = 'post-title'; heading.textContent = post.title || '投稿';
    article.append(heading, document.createTextNode(post.body));
    const actions = document.createElement('div'); actions.className = 'actions';
    if (post.user_id === user.id) actions.append(actionButton('削除', () => removePost(post.id), true));
    else actions.append(actionButton('通報', () => otakuReportContent('board', post.id)));
    if (isAdmin) actions.append(actionButton(post.pinned ? '固定解除' : '固定', async event => {
      event.currentTarget.disabled = true;
      const {error} = await otakuSupabase.rpc('otaku_set_board_pinned',{post_id:post.id,next_pinned:!post.pinned});
      if (error) alert('固定状態を変更できませんでした。'); await load();
    }));
    const replyForm = replyComposer(post.id);
    const replyToggle = actionButton(`返信する（${replies.length}件）`, () => {
      replyForm.hidden = !replyForm.hidden;
      if (!replyForm.hidden) replyForm.querySelector('textarea').focus();
    });
    actions.append(replyToggle); article.append(actions);
    if (replies.length) {
      const list = document.createElement('div'); list.className = 'replies';
      const count = document.createElement('div'); count.className = 'reply-count'; count.textContent = `返信 ${replies.length}件`;
      list.append(count, ...replies.map(renderReply)); article.append(list);
    }
    article.append(replyForm); return article;
  }
  async function load() {
    if (!user) { $('posts').textContent = '掲示板を見るにはログインしてください。'; return; }
    const selected = $('category').value;
    let query = otakuSupabase.from('otaku_board_posts').select('id,user_id,title,body,category,pinned,created_at,otaku_profiles(display_name,username)').eq('category',selected).order('pinned',{ascending:false}).order('created_at',{ascending:false});
    if (eventId) query = query.eq('event_id',eventId); else if (idolId) query = query.eq('idol_id',idolId); else query = query.is('event_id',null).is('idol_id',null);
    const {data:posts,error} = await query;
    if (error) { $('posts').textContent = '掲示板を読み込めませんでした。'; return; }
    let replies = [];
    if (posts.length) {
      const result = await otakuSupabase.from('otaku_board_replies').select('id,post_id,user_id,body,created_at,otaku_profiles(display_name,username)').in('post_id',posts.map(post=>post.id)).order('created_at');
      if (result.error) { $('posts').textContent = '返信を読み込めませんでした。'; return; }
      replies = result.data;
    }
    const byPost = new Map(posts.map(post => [post.id, []]));
    for (const reply of replies) byPost.get(reply.post_id)?.push(reply);
    $('posts').replaceChildren(...(posts.length ? posts.map(post => renderPost(post, byPost.get(post.id))) : [document.createTextNode('まだ投稿はありません。')]));
    if (location.hash) document.getElementById(location.hash.slice(1))?.scrollIntoView({block:'center'});
  }
  $('category').onchange = async () => {
    history.replaceState(null,'',boardUrl($('category').value));
    $('context').textContent = `カテゴリ：${labels[$('category').value]}`; await load();
  };
  $('send').onclick = async () => {
    const title = $('postTitle').value.trim(), body = $('body').value.trim();
    if (!title || !body || loading) return;
    loading = true; $('send').disabled = true;
    const row = {user_id:user.id,title,body,category:$('category').value};
    if (eventId) row.event_id=eventId; else if (idolId) row.idol_id=idolId;
    const {error} = await otakuSupabase.from('otaku_board_posts').insert(row);
    $('status').textContent = error ? '投稿できませんでした。' : '投稿しました。';
    if (!error) { $('postTitle').value=''; $('body').value=''; await load(); }
    loading = false; $('send').disabled = false;
  };
  (async () => {
    setupCategories(); user = await otakuGetUser();
    if (!user) {
      $('login').append('投稿・閲覧するには'); const link=document.createElement('a'); link.href=otakuLoginUrl(location.href); link.textContent='ログイン'; $('login').append(link,'してください。');
      $('composer').hidden=true;
    } else {
      $('login').textContent='ログイン中'; const result=await otakuSupabase.rpc('otaku_is_catalog_admin'); isAdmin=!result.error&&result.data===true;
    }
    $('title').textContent=eventId?'公演掲示板':idolId?'アイドル掲示板':'全体掲示板';
    $('context').textContent=`カテゴリ：${labels[$('category').value]}`; await load();
  })();
})();
