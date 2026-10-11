import { spawnSync } from 'node:child_process';

const services = [
  {
    label: 'Threads',
    envName: 'THREADS_TOKEN',
    secretName: 'THREADS_TOKEN',
    url: 'https://graph.threads.net/refresh_access_token?grant_type=th_refresh_token&access_token=',
  },
  {
    label: 'Instagram',
    envName: 'IG_TOKEN',
    secretName: 'IG_TOKEN',
    url: 'https://graph.instagram.com/refresh_access_token?grant_type=ig_refresh_token&access_token=',
  },
];

let failed = false;
const configured = services.filter(({ envName }) => process.env[envName]);

if (configured.length > 0 && !process.env.SECRETS_PAT) {
  console.error('エラー: SECRETS_PAT が未設定のため延長を実行できません');
  process.exit(1);
}

for (const service of services) {
  const token = process.env[service.envName];
  if (!token) {
    console.log(`${service.label}: スキップ（未設定）`);
    continue;
  }

  try {
    const response = await fetch(`${service.url}${encodeURIComponent(token)}`);
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      const message = typeof body.error?.message === 'string' ? body.error.message : '不明なエラー';
      console.log(`${service.label}: 延長NG（HTTP ${response.status}: ${message}）`);
      failed = true;
      continue;
    }

    if (typeof body.access_token !== 'string' || !Number.isFinite(body.expires_in)) {
      console.log(`${service.label}: 延長NG（HTTP ${response.status}: 応答形式が不正です）`);
      failed = true;
      continue;
    }

    const result = spawnSync(
      'gh',
      ['secret', 'set', service.secretName, '--repo', process.env.GITHUB_REPOSITORY],
      {
        input: body.access_token,
        env: { ...process.env, GH_TOKEN: process.env.SECRETS_PAT },
        encoding: 'utf8',
        stdio: ['pipe', 'ignore', 'pipe'],
      },
    );
    if (result.status !== 0) {
      console.log(`${service.label}: 延長NG（HTTP ${response.status}: Secrets の更新に失敗しました）`);
      failed = true;
      continue;
    }

    const days = Math.round(body.expires_in / 86400);
    console.log(`${service.label}: 延長OK（あと約${days}日）`);
  } catch (error) {
    const message = error instanceof Error ? error.message : '通信エラー';
    console.log(`${service.label}: 延長NG（HTTP 0: ${message}）`);
    failed = true;
  }
}

process.exitCode = failed ? 1 : 0;
