/* 気圧・体調アラーム ウィジェット — Service Worker
 *
 * スコープは /widget/ 配下のみ。サイト本体（政策分析ページ）には一切干渉しない。
 *
 * 方針:
 *   - アプリシェル（HTML・アイコン・マニフェスト）は事前キャッシュし、
 *     オフラインでもホーム画面から起動できるようにする。
 *   - 気象APIの応答はキャッシュしない。古い気圧データを表示するのは
 *     体調判断のうえで有害になりうるため、鮮度はネットワークに委ねる。
 *     オフライン時のフォールバックはページ側の localStorage が担い、
 *     「キャッシュ」と明示したうえで取得時刻とともに表示される。
 */

var VERSION = "v37";
var CACHE = "wxwidget-shell-" + VERSION;

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
        if(key !== CACHE) return caches.delete(key);
      }));
    }).then(function(){
      return self.clients.claim();
    }).then(function(){
      // 古い画面のまま止まっている窓を、こちら側から読み込み直させる。
      // ページ側の更新処理に頼ると、その処理が入っていない古い版が
      // 表示されている端末は永久に更新されない。
      return self.clients.matchAll({ type:"window" }).then(function(list){
        list.forEach(function(client){
          if(client && typeof client.navigate === "function"){
            try{ client.navigate(client.url).catch(function(){}); }
            catch(e){ /* 未対応の環境ではページ側の処理に任せる */ }
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

  // 気象・地名APIは常にネットワークへ。鮮度が要件なのでキャッシュしない。
  if(url.hostname.indexOf("open-meteo.com") !== -1) return;

  // 自分のスコープ外（他オリジン等）には介入しない。
  if(url.origin !== self.location.origin) return;
  if(url.pathname.indexOf(new URL("./", self.location.href).pathname) !== 0) return;

  // ナビゲーションは network-first。更新版を取りに行き、オフラインなら
  // キャッシュ済みのシェルを返す。
  if(req.mode === "navigate"){
    event.respondWith(
      // HTTPキャッシュを経由すると配信側の max-age の間だけ古いHTMLが
      // 返り、更新したはずの画面が変わらない。常に取り直す。
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

  // それ以外のシェル資産は cache-first（アイコン等は変わらないため）。
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
