// ios/Shared/Risk.swift と Models.swift を、1行ずつ JS に書き写したもの。
// 基準データ（Web 版が出した答え）と突き合わせて、移植ミスを探す。
const fs=require('fs');
const fx=JSON.parse(fs.readFileSync(require('path').join(__dirname,'..','Tests','Fixtures','judgement.json'),'utf8'));

const NOW = fx.fakeNowEpochMs;                 // Clock.now() を固定
const fmt1 = x => x.toFixed(1);

function makeForecast(c){
  const toDate = s => Date.parse(s + 'Z');     // 現地時刻を UTC として読む
  return {
    times: c.times.map(toDate),
    pressure: c.pressure, temp: c.temp, humidity: c.humidity,
    nowIndex: c.nowIndex, utcOffset: c.utcOffset,
    localNow(){ return NOW + this.utcOffset*1000; },
    back(a,i,n){ const j=i-n; if(j<0||i>=a.length) return null;
                 const x=a[j], y=a[i]; return (x==null||y==null)?null:y-x; },
    ahead(a,i,n){ const j=i+n; if(j>=a.length) return null;
                  const x=a[i], y=a[j]; return (x==null||y==null)?null:y-x; },
    dayRange(){
      const startOfDayUTC = ms => { const d=new Date(ms); d.setUTCHours(0,0,0,0); return d.getTime(); };
      const today = startOfDayUTC(this.localNow());
      let hi=null, lo=null;
      for(let i=0;i<this.times.length;i++){
        if(startOfDayUTC(this.times[i])!==today) continue;
        const v=this.temp[i]; if(v==null) continue;
        if(hi==null||v>hi) hi=v;
        if(lo==null||v<lo) lo=v;
      }
      return (hi==null||lo==null)?null:{hi,lo};
    }
  };
}

const W={past3:-2,past6:-3,future6:-3}, S={past3:-4,past6:-6,future6:-5}, C={past3:-6,past6:-9,future6:-8};
const ORDER={good:0,warning:1,serious:2,critical:3};

function score(d){
  const i=d.nowIndex;
  const fall = x => Math.max(0, -(x==null?0:x));
  const sp = Math.max(
    fall(d.back(d.pressure,i,3))/0.7,
    fall(d.back(d.pressure,i,6))/1.25,
    fall(d.ahead(d.pressure,i,6))/1.5
  );
  const hum=d.humidity[i], tp=d.temp[i];
  let sh=0;
  if(hum!=null){
    if(hum>62) sh += (hum-62)/9;
    if(hum<=32) sh += (32-hum)/11;
    if(hum>=72 && tp!=null && tp>=25) sh += 1.0;
  }
  sh=Math.min(4.5,sh);
  let st = fall(d.back(d.temp,i,3))/4 + fall(d.ahead(d.temp,i,6))/6;
  if(tp!=null && (tp<=5||tp>=31)) st += 0.8;
  st=Math.min(1.5,st);
  return Math.max(0, Math.min(9, Math.round(sp+sh+st)));
}

function levelOf(delta, pick){
  if(delta==null) return 'good';
  if(delta<=pick(C)) return 'critical';
  if(delta<=pick(S)) return 'serious';
  if(delta<=pick(W)) return 'warning';
  return 'good';
}
const pastPhrase = r => r==null?'確認中':
  r<=-6?'急降下しています': r<=-4?'大きく下降中': r<=-2?'下降しています':
  r<=-0.8?'ゆるやかに低下': r<0.8?'落ち着いています': r<2.5?'ゆるやかに回復':'上昇しています';
const futurePhrase = r => r==null?'確認中': r<=-8?'まもなく急降下': r<=-5?'まもなく大きく下降':'これから下がります';
const NPW={muggy:'蒸し暑さが重なっています',humid:'湿度が高い状態です',dry:'空気が乾いています',
  hot:'気温が高い状態です',cold:'気温が低い状態です',tempFall:'気温が下がっています',
  tempRise:'気温が上がっています',coolDown:'この先気温が下がります',swing:'気温差が大きい一日です'};

function weatherNotes(d){
  const i=d.nowIndex, hum=d.humidity[i], tp=d.temp[i];
  const dT3=d.back(d.temp,i,3), fT6=d.ahead(d.temp,i,6);
  const out=[];
  if(dT3!=null && dT3<=-4) out.push({kind:'tempFall', text:'3時間で気温 '+fmt1(dT3)+'°'});
  if(dT3!=null && dT3>=5)  out.push({kind:'tempRise', text:'3時間で気温 +'+fmt1(dT3)+'°'});
  if(hum!=null&&tp!=null&&hum>=80&&tp>=24) out.push({kind:'muggy', text:'湿度 '+Math.round(hum)+'%'});
  else if(hum!=null&&hum>=85) out.push({kind:'humid', text:'湿度 '+Math.round(hum)+'%'});
  else if(hum!=null&&hum<=30) out.push({kind:'dry',   text:'湿度 '+Math.round(hum)+'%'});
  const day=d.dayRange();
  if(day && day.hi-day.lo>=10) out.push({kind:'swing', text:'気温差 '+Math.round(day.hi-day.lo)+'°'});
  if(fT6!=null&&fT6<=-5) out.push({kind:'coolDown', text:'この先6時間 '+fmt1(fT6)+'°'});
  if(tp!=null&&tp<=5)  out.push({kind:'cold', text:'気温 '+fmt1(tp)+'°'});
  if(tp!=null&&tp>=30) out.push({kind:'hot',  text:'気温 '+fmt1(tp)+'°'});
  return out;
}

function alarm(d){
  const i=d.nowIndex;
  const d3=d.back(d.pressure,i,3), d6=d.back(d.pressure,i,6), f6=d.ahead(d.pressure,i,6);
  const lv=[levelOf(d3,t=>t.past3), levelOf(d6,t=>t.past6), levelOf(f6,t=>t.future6)];
  let lvl=lv.reduce((m,x)=>ORDER[x]>ORDER[m]?x:m,'good');
  const futureLeads = ORDER[lv[2]] > Math.max(ORDER[lv[0]],ORDER[lv[1]]);
  let word = futureLeads ? futurePhrase(f6) : pastPhrase(d3);
  const notes = weatherNotes(d);
  const pressureLevel = lvl;
  const risk = score(d);
  const byRisk = risk>=7?'critical': risk>=5?'serious': risk>=3?'warning':'good';
  if(ORDER[byRisk]>ORDER[lvl]){
    lvl = byRisk;
    word = NPW[notes.length?notes[0].kind:''] || '気圧以外の負荷があります';
  }
  const lines=[];
  if(pressureLevel!=='good'){
    const c=[];
    if(d3!=null && ORDER[lv[0]]>0) c.push([d3,'3時間 '+fmt1(d3)+'hPa']);
    if(d6!=null && ORDER[lv[1]]>0) c.push([d6,'6時間 '+fmt1(d6)+'hPa']);
    if(f6!=null && ORDER[lv[2]]>0) c.push([f6,'この先6時間 '+fmt1(f6)+'hPa']);
    c.sort((a,b)=>a[0]-b[0]);
    if(c.length) lines.push(c[0][1]);
    if(notes.length) lines.push(notes[0].text);
  }else{
    notes.slice(0,2).forEach(n=>lines.push(n.text));
  }
  return { level:lvl, word, note:lines.join(' · '), risk };
}

let bad=[], kinds={};
fx.cases.forEach((c,n)=>{
  const a=alarm(makeForecast(c)), e=c.expect;
  const diff=[];
  if(a.risk!==e.risk)   diff.push(`危険度 ${a.risk}≠${e.risk}`);
  if(a.level!==e.level) diff.push(`段階 ${a.level}≠${e.level}`);
  if(a.word!==e.word)   diff.push(`見出し「${a.word}」≠「${e.word}」`);
  if(a.note!==e.note)   diff.push(`注記「${a.note}」≠「${e.note}」`);
  if(diff.length){ bad.push(`${n}件目: ${diff.join(' / ')}`); diff.forEach(d=>{const k=d.split(' ')[0].split('「')[0]; kinds[k]=(kinds[k]||0)+1;}); }
});
console.log(`突き合わせ ${fx.cases.length} 件`);
console.log(bad.length ? `★ 不一致 ${bad.length} 件\n` + bad.slice(0,12).join('\n') : '◎ 全件一致');
if(bad.length) console.log('\n内訳:', JSON.stringify(kinds));
