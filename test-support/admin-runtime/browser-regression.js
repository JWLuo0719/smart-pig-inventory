// Playwright CLI run-code function. Config is generated only in ignored local evidence.
async (page) => {
  const config = __RUNTIME_CONFIG__;
  const check = (condition, label) => { if (!condition) throw new Error(label); };
  const errors = [];
  let stage = 'login';
  try {
  page.on('pageerror', (error) => errors.push(error.message));
  let refreshes = 0;
  page.on('request', (request) => {
    if (request.url().endsWith('/api/backend/auth/refresh')) refreshes++;
  });
  await page.goto(config.baseUrl);
  await page.getByLabel('账号', { exact: true }).fill('e2e-farm-admin');
  await page.getByLabel('口令', { exact: true }).fill(config.password);
  const loginResponse = page.waitForResponse((r) => r.url().endsWith('/api/backend/auth/login'));
  await page.getByRole('button', { name: '登录并加载数据' }).click();
  const login = await (await loginResponse).json();
  await page.getByRole('heading', { name: '现场盘点态势' }).waitFor();
  const refreshButton = page.getByRole('button', { name: '刷新', exact: true });
  await page.waitForFunction(() => !document.querySelector('#tasks button').disabled);
  check(await page.locator('[role="alert"]').filter({ hasText: /\S/ }).count() === 0, 'Initial dashboard must load without errors');
  const task = page.locator('#tasks article').filter({ hasText: config.sourceCode });
  check(await task.count() === 1, 'Isolated correction task must exist exactly once');
  check((await task.innerText()).includes('17'), 'Task must read real v1 count');
  const failure = page.locator('#inference-failures article').filter({ has: page.locator(`[title="${config.failedJobId}"]`) });
  check(await failure.count() === 1, 'Failed job must be returned through same-origin route');

  // Wait for the server to reject the original token, including JWT clock skew.
  stage = 'real-token-expiry';
  // Poll a real endpoint, do not mock 401 or change product JWT validation.
  const expiryDeadline = Date.now() + 100000;
  let expired = false;
  while (Date.now() < expiryDeadline) {
    const probe = await page.request.get(`${config.baseUrl}/api/backend/me`, { headers: { Authorization: `Bearer ${login.accessToken}` } });
    if (probe.status() === 401) { expired = true; break; }
    check(probe.ok(), 'Expiry probe must not mistake a server failure for expiration');
    await page.waitForTimeout(1000);
  }
  check(expired, 'Original access token must expire within the test deadline');
  const rotatedResponse = page.waitForResponse((r) => r.url().endsWith('/api/backend/auth/refresh'));
  await refreshButton.click();
  const rotated = await (await rotatedResponse).json();
  await page.waitForFunction(() => !document.querySelector('#tasks button').disabled);
  check(refreshes === 1, 'Expired concurrent dashboard requests must rotate only once');
  check(await page.locator('[role="alert"]').filter({ hasText: /\S/ }).count() === 0, 'Refresh must restore the dashboard');
  check(await page.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0), 'Tokens must remain memory-only');

  stage = 'correction-ui';
  await task.getByRole('button', { name: '查看会话证据' }).click();
  await page.getByRole('heading', { name: `${config.date} · confirmed · v1`, exact: true }).waitFor();
  await page.getByText('证据已锁定', { exact: true }).waitFor();
  await page.waitForFunction(() => {
    const image = document.querySelector('#media-review img');
    return image && image.complete && image.naturalWidth > 0;
  });
  const reason = 'Synthetic runtime correction with preserved original evidence';
  const answers = ['19', reason];
  const dialogHandler = (dialog) => dialog.accept(answers.shift());
  page.on('dialog', dialogHandler);
  const correctionResponse = page.waitForResponse((r) => r.url().endsWith(`/inventory-sessions/${config.sourceId}/corrections`));
  await page.getByRole('button', { name: '创建审计更正版本' }).click();
  const response = await correctionResponse;
  check(response.ok(), 'Correction POST must succeed');
  const correction = await response.json();
  const correctionKey = response.request().headers()['x-idempotency-key'];
  page.off('dialog', dialogHandler);
  await page.getByRole('heading', { name: `${config.date} · confirmed · v2`, exact: true }).waitFor();
  await page.waitForFunction(() => !document.querySelector('#tasks button').disabled);
  check((await task.innerText()).includes('19'), 'Task must switch to v2 count');
  const reportRow = page.locator('#reports li').filter({ hasText: config.sourceCode });
  check(await reportRow.count() === 1 && (await reportRow.innerText()).includes('19 头'), 'Daily UI must show only v2');

  // Real HTTP semantic readback with the same browser session's current access token.
  stage = 'correction-readback';
  const headers = { Authorization: `Bearer ${rotated.accessToken}` };
  const api = `${config.baseUrl}/api/backend`;
  const read = async (path) => {
    const result = await page.request.get(`${api}/${path}`, { headers });
    check(result.ok(), `Readback failed: ${path} (${result.status()})`);
    return result.json();
  };
  const source = await read(`inventory-sessions/${config.sourceId}`);
  check(source.status === 'superseded' && source.count === 17 && source.version === 1, 'Historical v1 must preserve count');
  check(correction.supersedesSessionId === source.id && correction.evidenceSessionId === source.id && correction.count === 19, 'Correction lineage must reference v1');
  const oldMedia = await read(`inventory-sessions/${source.id}/media`);
  const newMedia = await read(`inventory-sessions/${correction.id}/media`);
  check(oldMedia.length === 1 && JSON.stringify(oldMedia) === JSON.stringify(newMedia) && newMedia[0].locked, 'v2 must retain the same locked evidence');
  const daily = (await read(`inventory-reports/daily?businessDate=${config.date}`)).filter((row) => row.penId === config.sourcePen);
  check(daily.length === 1 && daily[0].sessionId === correction.id && daily[0].confirmedCount === 19, 'Confirmed-only HTTP report must exclude v1');
  const writeHeaders = { ...headers, 'X-Idempotency-Key': correctionKey };
  const replay = await page.request.post(`${api}/inventory-sessions/${source.id}/corrections`, { headers: writeHeaders, data: { correctedCount: 19, reason: `  ${reason}  ` } });
  check(replay.ok() && (await replay.json()).id === correction.id, 'Normalized correction replay must return the same v2');
  const conflict = await page.request.post(`${api}/inventory-sessions/${source.id}/corrections`, { headers: writeHeaders, data: { correctedCount: 20, reason } });
  check(conflict.status() === 409, 'Changed correction payload must conflict');
  const audit = await read('audit-events?limit=100');
  check(audit.filter((event) => event.action === 'inventory.corrected' && event.targetId === correction.id && event.reason === reason).length === 1, 'Correction replay must not duplicate audit');

  stage = 'retry-ui';
  page.once('dialog', (dialog) => dialog.accept('Synthetic runtime retry preserving original failure evidence'));
  const retryResponse = page.waitForResponse((r) => r.url().endsWith(`/inference-jobs/${config.failedJobId}/retries`));
  await failure.getByRole('button', { name: '保留证据并重试' }).click();
  const retryHttp = await retryResponse;
  check(retryHttp.ok(), 'Failed-job retry POST must reach backend');
  const retry = await retryHttp.json();
  await page.waitForFunction(() => !document.querySelector('#tasks button').disabled);
  check(await failure.getByRole('button', { name: '已创建后继任务' }).isDisabled(), 'Original failure must show immutable successor');

  stage = 'authorization-boundaries';
  for (const username of ['e2e-operator', 'e2e-second-operator']) {
    const loginHttp = await page.request.post(`${api}/auth/login`, { headers: { 'X-Idempotency-Key': 'b6dc0528-67d6-41fb-9b91-4dfe2aa602c6' }, data: { username, password: config.password } });
    check(loginHttp.ok(), 'Role fixture login must succeed');
    const pair = await loginHttp.json();
    const denied = await page.request.post(`${api}/inventory-sessions/${correction.id}/corrections`, { headers: { Authorization: `Bearer ${pair.accessToken}`, 'X-Idempotency-Key': 'b6dc0528-67d6-41fb-9b91-4dfe2aa602c7' }, data: { correctedCount: 20, reason } });
    check(denied.status() === 404, 'Operator/cross-organization correction must be hidden');
  }

  // Faults below are browser-only synthetic responses; normal business readbacks above are real.
  stage = 'optional-panel-states';
  const panelCases = [
    { id: 'duplicate-review', route: '**/api/backend/review/near-duplicates', empty: '暂无待处理告警' },
    { id: 'inference-failures', route: '**/api/backend/inference-jobs/failed?limit=50', empty: '当前组织暂无失败推理任务。' },
    { id: 'audit', route: '**/api/backend/audit-events?limit=30', empty: '当前组织暂无审计记录。' },
  ];
  let faultChecks = 0;
  for (const item of panelCases) {
    const panel = page.locator(`#${item.id}`);
    for (const mode of ['503', '404', 'network', 'malformed', 'empty']) {
      let release;
      const held = new Promise((resolve) => { release = resolve; });
      await page.route(item.route, async (route) => {
        await held;
        if (mode === 'network') await route.abort('failed');
        else await route.fulfill({ status: mode === '503' ? 503 : mode === '404' ? 404 : 200, contentType: 'application/json', body: mode === 'empty' ? '[]' : mode === 'malformed' ? '{invalid' : '{"detail":"synthetic fault"}' });
      });
      await refreshButton.click();
      await panel.getByText('正在加载，请稍候…', { exact: true }).waitFor();
      check(await panel.locator('article, .queue-list li').count() === 0, 'Loading must hide stale panel rows');
      release();
      await page.waitForFunction(() => !document.querySelector('#tasks button').disabled);
      if (mode === 'empty') {
        check((await panel.getByRole('status').innerText()).includes(item.empty), 'Only a successful empty response may show empty state');
        check(await panel.getByRole('alert').count() === 0, 'Empty response is not an error');
      } else {
        check((await panel.getByRole('alert').innerText()).includes('加载失败'), `${item.id} ${mode} must be a visible load error`);
        check(!(await panel.innerText()).includes(item.empty), 'Failed panel must not claim empty data');
        check(!(await panel.innerText()).includes('无此面板'), 'Masked 404/network failure must not be guessed as denied');
      }
      check((await task.innerText()).includes('19'), 'Optional fault must not discard confirmed tasks');
      const siblingAlerts = await page.locator('#duplicate-review [role="alert"], #inference-failures [role="alert"], #audit [role="alert"]').count();
      check(siblingAlerts === (mode === 'empty' ? 0 : 1), 'Optional fault must not fail sibling panels');
      if (item.id === 'duplicate-review') {
        const count = await page.locator('.attention-counts > strong').filter({ hasText: '近重复告警' }).innerText();
        check(count.startsWith(mode === 'empty' ? '0' : '—'), 'Unknown duplicate count must not display zero');
      }
      await page.unroute(item.route);
      if (mode === 'empty') await refreshButton.click();
      else await panel.getByRole('button', { name: '刷新重试', exact: true }).click();
      await page.waitForFunction(() => !document.querySelector('#tasks button').disabled);
      check(await page.locator('[role="alert"]').filter({ hasText: /\S/ }).count() === 0, 'Reload must recover all panels');
      faultChecks++;
    }
  }
  await page.screenshot({ path: 'dashboard.png', fullPage: true });

  stage = 'master-data-and-history';
  const master = page.locator('#master-data');
  await master.getByRole('button', { name: '新增栋舍', exact: true }).click();
  const buildingForm = master.getByRole('form', { name: '维护栋舍' });
  const buildingCode = `UI-${Date.now()}`;
  await buildingForm.getByLabel('编码', { exact: true }).fill(buildingCode);
  await buildingForm.getByLabel('名称', { exact: true }).fill('Synthetic UI building');
  await buildingForm.getByLabel('变更原因').fill('Synthetic functional acceptance');
  const buildingSaved = page.waitForResponse(r => r.request().method() === 'PUT' && r.url().includes('/master-data/buildings/'));
  await buildingForm.getByRole('button', { name: '保存资料' }).click();
  const buildingResponse = await buildingSaved;
  check(buildingResponse.ok(), 'Building UI write must succeed');
  const building = await buildingResponse.json();
  await master.getByRole('button', { name: `编辑栋舍 ${buildingCode}`, exact: true }).waitFor();
  await master.getByRole('button', { name: '新增栏舍', exact: true }).click();
  const penForm = master.getByRole('form', { name: '维护栏舍' });
  const penCode = `P-${buildingCode}`;
  await penForm.getByLabel('所属栋舍').selectOption(building.id);
  await penForm.getByLabel('编码', { exact: true }).fill(penCode);
  await penForm.getByLabel('名称', { exact: true }).fill('Synthetic UI pen');
  await penForm.getByLabel('变更原因').fill('Synthetic functional acceptance');
  const penSaved = page.waitForResponse(r => r.request().method() === 'PUT' && r.url().includes('/master-data/pens/'));
  await penForm.getByRole('button', { name: '保存资料' }).click();
  const penResponse = await penSaved;
  check(penResponse.ok(), 'Pen UI write must succeed');
  const createdPen = await penResponse.json();
  check(createdPen.parentId === building.id, 'Pen must retain its selected parent');
  await master.getByRole('button', { name: `编辑栏舍 ${penCode}`, exact: true }).waitFor();
  const history = page.locator('#inventory-history');
  await history.getByRole('button', { name: '查询历史盘点' }).click();
  await history.getByRole('heading', { name: '已确认日报' }).waitFor();
  const historyRecord = history.locator('li').filter({ hasText: config.sourceCode });
  check(await historyRecord.count() === 2, 'History must show both confirmed report and task');
  check((await historyRecord.first().innerText()).includes('19 头'), 'Historical report must read corrected count');
  await history.getByLabel('综合栏舍').selectOption(correction.penId);
  await history.getByRole('button', { name: '查询历史盘点' }).click();
  await history.getByRole('status').filter({ hasText: '原始均值 19' }).waitFor();
  const functionalLogin = await page.request.post(`${api}/auth/login`, { headers: { 'X-Idempotency-Key': 'fcde4122-ef59-4b34-a811-4b205f032908' }, data: { username: 'e2e-farm-admin', password: config.password } });
  check(functionalLogin.ok(), 'Functional readback login must succeed');
  const functionalHeaders = { Authorization: `Bearer ${(await functionalLogin.json()).accessToken}` };
  const changesResponse = await page.request.get(`${api}/master-data/changes`, { headers: functionalHeaders });
  check(changesResponse.ok(), 'Master-data semantic readback must succeed');
  const changes = await changesResponse.json();
  check(changes.buildings.some(b => b.id === building.id && b.code === buildingCode) && changes.pens.some(p => p.id === createdPen.id && p.parentId === building.id), 'Persisted hierarchy must match the UI');
  const libraryResponse = await page.request.get(`${api}/media-assets?businessDate=${config.date}&penId=${correction.penId}`, { headers: functionalHeaders });
  check(libraryResponse.ok(), 'Library route must be available through the proxy');
  const library = await libraryResponse.json();
  check(library.length === 1 && library[0].locked && !library[0].deleted, 'Library must expose only selected pen evidence with its real lock');
  stage = 'admin-evidence-override';
  await historyRecord.getByRole('button', { name: '查看确认记录', exact: true }).click();
  // The CLI can yield again on a third native dialog while its completion reader is active.
  // Supply this synthetic reason synchronously; the click, HTTP authorization and readback stay real.
  await page.evaluate(() => { window.__runtimeOriginalPrompt = window.prompt; window.prompt = () => 'Synthetic administrator removed incorrect evidence'; });
  const overrideSaved = page.waitForResponse(r => r.request().method() === 'POST' && r.url().endsWith(`/media-assets/${library[0].assetId}/override-delete`));
  await page.getByRole('button', { name: '管理员覆盖删除', exact: true }).click();
  check((await overrideSaved).status() === 200, 'Administrator evidence override must return its contracted 200 response');
  await page.evaluate(() => { window.prompt = window.__runtimeOriginalPrompt; delete window.__runtimeOriginalPrompt; });
  await page.locator('#media-review').getByText('已删除', { exact: false }).waitFor();
  await page.waitForFunction(() => !document.querySelector('#tasks button').disabled);
  check((await task.innerText()).includes('19'), 'Evidence override must not rewrite confirmed count');
  check(await page.locator('#audit article').filter({ hasText: 'media.override_deleted' }).count() > 0, 'Evidence override must have a real audit event');
  await page.screenshot({ path: 'functional-dashboard.png', fullPage: true });

  stage = 'panel-role-presentation';
  const roleChecks = [];
  for (const username of ['e2e-operator', 'e2e-reviewer']) {
    await page.reload();
    await page.getByLabel('账号', { exact: true }).fill(username);
    await page.getByLabel('口令', { exact: true }).fill(config.password);
    const requested = [];
    const collect = (request) => { if (/\/(review\/near-duplicates|inference-jobs\/failed|audit-events)(\?|$)/.test(request.url())) requested.push(request.url()); };
    page.on('request', collect);
    await page.getByRole('button', { name: '登录并加载数据' }).click();
    await page.getByRole('heading', { name: '现场盘点态势' }).waitFor();
    await page.waitForFunction(() => !document.querySelector('#tasks button').disabled);
    for (const id of username === 'e2e-operator' ? ['duplicate-review', 'inference-failures', 'audit'] : ['inference-failures', 'audit']) {
      check((await page.locator(`#${id}`).getByRole('status').innerText()).includes('无此面板的查看权限'), 'Known role denial must have its own presentation');
      check(await page.locator(`#${id} article, #${id} .queue-list li`).count() === 0, 'New login must not reveal previous admin rows');
    }
    check(requested.length === (username === 'e2e-operator' ? 0 : 1), 'Do not request known unauthorized panels');
    check(await page.locator('#master-data').getByRole('button', { name: '新增栋舍', exact: true }).count() === 0, 'Non-admins must not see master-data write controls');
    check(await page.locator('[role="alert"]').filter({ hasText: /\S/ }).count() === 0, 'Denied panels must not break the dashboard');
    page.off('request', collect);
    roleChecks.push(username);
  }
  await page.reload();
  await page.getByRole('heading', { name: '登录现场作业台' }).waitFor();
  check(errors.length === 0, `Browser errors: ${errors.join('; ')}`);
  const summary = { status: 'passed', completedAt: new Date().toISOString(), composeProject: 'pig-inventory-p0-admin-runtime', refreshes, v1: source.id, v2: correction.id, oldCount: 17, correctedCount: 19, mediaLocked: true, retry, correctionReplay: true, conflictStatus: 409, deniedStatus: 404, memoryOnly: true, optionalPanelChecks: faultChecks, panelRoleChecks: roleChecks, browserErrors: errors.length, humanAcceptance: 'pending' };
  summary.functionalChecks = { masterDataUi: true, hierarchyReadback: true, historicalConfirmedOnly: true, aggregate: true, libraryScoped: true, administrativeDeletionAudited: true };
  // CLI can yield early when a native prompt opens. Publish only sanitized final evidence.
  await page.evaluate((result) => { window.__adminRuntimeResult = result; }, summary);
  return summary;
  } catch (error) {
    await page.screenshot({ path: 'failure.png', fullPage: true }).catch(() => {});
    const failure = { status: 'failed', stage, error: error.message, completedAt: new Date().toISOString() };
    await page.evaluate((result) => { window.__adminRuntimeResult = result; }, failure);
    return failure;
  }
}
