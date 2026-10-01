const trigger = document.querySelector('#quality-trigger');
const menu = document.querySelector('#quality-menu');
const options = [...menu.querySelectorAll('[role="option"]')];
const feedback = document.querySelector('#feedback');
const selectedIndex = () => options.findIndex(x => x.getAttribute('aria-selected') === 'true');
function closeQuality(restoreFocus = false) {
  menu.hidden = true; trigger.setAttribute('aria-expanded', 'false');
  if (restoreFocus) trigger.focus();
}
function openQuality(index = selectedIndex()) {
  menu.hidden = false; trigger.setAttribute('aria-expanded', 'true'); options[index].focus();
}
trigger.addEventListener('click', () => menu.hidden ? openQuality() : closeQuality(true));
trigger.addEventListener('keydown', e => {
  if (['ArrowDown', 'ArrowUp'].includes(e.key)) { e.preventDefault(); openQuality(e.key === 'ArrowUp' ? options.length - 1 : selectedIndex()); }
});
options.forEach((option, index) => {
  option.addEventListener('click', () => {
    options.forEach(x => x.setAttribute('aria-selected', String(x === option)));
    document.querySelector('#quality-value').textContent = option.dataset.value;
    closeQuality(true);
  });
  option.addEventListener('keydown', e => {
    let next;
    if (e.key === 'ArrowDown') next = (index + 1) % options.length;
    if (e.key === 'ArrowUp') next = (index + options.length - 1) % options.length;
    if (e.key === 'Home') next = 0;
    if (e.key === 'End') next = options.length - 1;
    if (next !== undefined) { e.preventDefault(); options[next].focus(); }
    if (e.key === 'Escape') { e.preventDefault(); closeQuality(true); }
  });
});
document.addEventListener('click', e => { if (!e.target.closest('.quality')) closeQuality(); });
menu.addEventListener('focusout', () => requestAnimationFrame(() => {
  if (!document.activeElement.closest('.quality')) closeQuality();
}));
document.querySelectorAll('.seg button').forEach(b => b.addEventListener('click', () => {
  document.querySelectorAll('.seg button').forEach(x => { x.classList.toggle('active', x === b); x.setAttribute('aria-pressed', String(x === b)); });
  const audio = b.dataset.format === 'audio';
  trigger.disabled = audio;
  trigger.title = audio ? '音频模式无需选择视频画质' : '';
  closeQuality();
}));
function displayFolder(path) {
  const label = document.querySelector('#destination-path');
  label.textContent = path; label.title = path;
}
fetch('/api/destination').then(r => { if (!r.ok) throw Error(); return r.json(); })
  .then(data => displayFolder(data.path)).catch(() => { feedback.textContent = '文件夹选择服务未连接，请通过本地预览地址打开。'; });
const folderButton = document.querySelector('#choose-folder');
folderButton.addEventListener('click', async () => {
  folderButton.disabled = true;
  feedback.textContent = '请在 macOS 窗口中选择保存文件夹…';
  try {
    const response = await fetch('/api/choose-folder', { method: 'POST', headers: { 'X-Preview-Action': 'choose-folder' } });
    const result = await response.json();
    if (!response.ok) throw Error(result.error || '未能选择文件夹。');
    if (result.path) { displayFolder(result.path); feedback.textContent = '已记住保存位置。当前为交互预览，尚未执行下载。'; }
    else feedback.textContent = '已取消，保存位置未改变。';
  } catch (error) { feedback.textContent = error.message || '文件夹选择失败，请重试。'; }
  finally { folderButton.disabled = false; }
});
document.querySelectorAll('.action,#extract').forEach(b => b.addEventListener('click', () => {
  feedback.textContent = '这是交互预览，未执行下载或修改任务。';
}));
