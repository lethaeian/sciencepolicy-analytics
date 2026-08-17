/* 家計 — Service Worker
 *
 * スコープは /kakeibo/ 配下のみ。サイト本体（政策分析ページ）や
 * 他のウィジェットには一切干渉しない。
 *
 * 方針:
 *   - 外部と通信しないアプリなので、シェル一式を事前キャッシュして
 *     完全にオフラインで動くようにする。記録は端末の localStorage にだけ残る。
 *   - HTML は network-first。更新版があれば取りに行き、無ければ手元の版を返す。
 */

var VERSION = "v5";
var CACHE = "kakeibo-shell-" + VERSION;

var SHELL = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./icon-192.png",
  "./icon-512.png",
  "./icon-maskable-512.png",
  "./apple-touch-icon.png"
];

self.addEventListener("install", function(event){
  event.waitUntil(
    caches.open(CACHE).then(function(cache){
      return cache.addAll(SHELL);
    }).then(function(){
      return self.skipWaiting();
    })
  );
});

self.addEventListener("activate", function(event){
  event.waitUntil(
    caches.keys().then(function(keys){
      return Promise.all(keys.map(function(key){
        if(key.indexOf("kakeibo-shell-") === 0 && key !== CACHE) return caches.delete(key);
      }));
    }).then(function(){
      return self.clients.claim();
    }).then(function(){
      // 古い画面のまま開きっぱなしの窓を、こちら側から読み込み直させる。
      return self.clients.matchAll({ type:"window" }).then(function(list){
        list.forEach(function(client){
          if(client && typeof client.navigate === "function"){
            try{ client.navigate(client.url).catch(function(){}); }
            catch(e){ /* 未対応の環境では次回起動時に更新される */ }
          }
        });
      });
    })
  );
});

self.addEventListener("fetch", function(event){
  var req = event.request;
  if(req.method !== "GET") return;

  var url;
  try{ url = new URL(req.url); }catch(e){ return; }

  // 自分のスコープ外には介入しない。
  if(url.origin !== self.location.origin) return;
  if(url.pathname.indexOf(new URL("./", self.location.href).pathname) !== 0) return;

  if(req.mode === "navigate"){
    event.respondWith(
      // HTTPキャッシュを経由すると配信側の max-age の間だけ古いHTMLが返る。常に取り直す。
      fetch(req, { cache:"no-store" }).then(function(res){
        var copy = res.clone();
        caches.open(CACHE).then(function(cache){ cache.put("./index.html", copy); });
        return res;
      }).catch(function(){
        return caches.match("./index.html").then(function(hit){
          return hit || caches.match("./");
        });
      })
    );
    return;
  }

  event.respondWith(
    caches.match(req).then(function(hit){
      if(hit) return hit;
      return fetch(req).then(function(res){
        if(res && res.status === 200 && res.type === "basic"){
          var copy = res.clone();
          caches.open(CACHE).then(function(cache){ cache.put(req, copy); });
        }
        return res;
      });
    })
  );
});
