/* 宇宙技芸 八稜鏡 — Service Worker
 *
 * スコープは /cosmotechnics/ 配下のみ。サイト本体（政策分析ページ）にも
 * /widget/ の気圧ウィジェットにも一切干渉しない。
 *
 * 読み替えの処理はすべて端末内で完結するため、通信は起動時だけ。
 * シェルを事前キャッシュしておけば、以後は完全にオフラインで動く。
 */

/* index.html の VERSION と version.json に揃えること。 */
var VERSION = "2026.08.14-3";
var CACHE = "cosmotechnics-shell-" + VERSION;

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
        if(key.indexOf("cosmotechnics-shell-") === 0 && key !== CACHE){
          return caches.delete(key);
        }
      }));
    }).then(function(){
      return self.clients.claim();
    })
  );
});

self.addEventListener("fetch", function(event){
  var req = event.request;
  if(req.method !== "GET") return;

  var url;
  try{ url = new URL(req.url); }catch(e){ return; }

  // 自分のスコープ外には介入しない（Anthropic API もここで素通しになる）。
  if(url.origin !== self.location.origin) return;

  // 版の確認は常にネットワークへ。キャッシュすると更新が見えなくなる。
  if(url.pathname.indexOf("version.json") !== -1) return;
  if(url.pathname.indexOf(new URL("./", self.location.href).pathname) !== 0) return;

  // ナビゲーションは network-first。更新版があれば取りに行き、
  // オフラインならキャッシュ済みのシェルを返す。
  // 共有シートからの ?text=... も同じ index.html で受ける。
  if(req.mode === "navigate"){
    event.respondWith(
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

  // アイコン等は変わらないので cache-first。
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
