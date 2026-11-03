// Jailbreak (WebKit Autoloader X) header — runs after upstream's app.js through
// the PAGE_JS hook, so app.js stays untouched. Styles live in theme-x.css.
(function () {
  'use strict';
  var loader = document.getElementById('loader');
  if (!loader || document.getElementById('xHeader')) return;

  var header = document.createElement('header');
  header.id = 'xHeader';
  var title = document.createElement('div');
  title.className = 'x-title';
  title.textContent = 'JAILBREAK';
  var sub = document.createElement('div');
  sub.className = 'x-sub';
  sub.textContent = 'WebKit · Payload Manager X';
  header.appendChild(title);
  header.appendChild(sub);
  loader.insertBefore(header, loader.firstChild);
})();
