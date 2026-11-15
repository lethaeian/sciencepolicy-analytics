// Web 版の判定関数をそのまま取り出し、無作為な入力に対する答えを書き出す。
// SwiftUI 版が同じ答えを返すかを、Xcode 側のテストで確かめるための基準。
const fs=require('fs');
const src=fs.readFileSync(require('path').join(__dirname,'..','..','widget','index.html'),'utf8');
const js=src.match(/<script>([\s\S]*?)<\/script>/)[1];

function grab(name, kind){
  const re = kind==='var'
    ? new RegExp(`\\n  var ${name} = \\{[\\s\\S]*?\\n  \\};`)
    : new RegExp(`\\n  function ${name}\\([\\s\\S]*?\\n  \\}`);
  const m = js.match(re);
  if(!m) throw new Error('見つからない: '+name);
  return m[0];
}
const parts = [
  grab('THRESH','var'), grab('ORDER','var'), grab('NON_PRESSURE_WORD','var'),
  grab('back'), grab('ahead'), grab('levelFor'),
  grab('pastPhrase'), grab('futurePhrase'),
  grab('weatherNotes'), grab('dayRange'), grab('riskOf'), grab('computeAlarm'),
];
const sandbox = new Function('NOW', parts.join('\n') + `
  return { riskOf, computeAlarm };
`);

// 再現できる疑似乱数
let seed = 20261115;
function rnd(){ seed = (seed*1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; }
function pick(a){ return a[Math.floor(rnd()*a.length)]; }

const FAKE = Date.parse('2026-08-12T05:47:00Z');   // 14:47 JST
const OFFSET = 9*3600;
const realNow = Date.now;
Date.now = () => FAKE;
const { riskOf, computeAlarm } = sandbox(FAKE);

const cases=[];
for(let c=0;c<240;c++){
  const start=new Date(FAKE+OFFSET*1000);
  start.setUTCMinutes(0,0,0); start.setUTCHours(0); start.setUTCDate(start.getUTCDate()-1);
  const n=Math.floor((FAKE+OFFSET*1000-start.getTime())/3600e3);
  const shape=pick(['flat','fall','rise','wave','crash','spike']);
  const p0 = 990 + rnd()*40;
  const h0 = 15 + rnd()*80;
  const t0 = -8 + rnd()*44;
  const times=[],pressure=[],temp=[],humidity=[];
  for(let i=0;i<72;i++){
    times.push(new Date(start.getTime()+i*3600e3).toISOString().slice(0,16));
    let p=p0, t=t0, h=h0;
    const k=i-n;
    if(shape==='fall')  p = p0 - Math.max(0,k+6)*0.4;
    if(shape==='rise')  p = p0 + Math.max(0,k+6)*0.5;
    if(shape==='wave')  p = p0 + Math.sin(i/2.3)*3;
    if(shape==='crash') p = p0 - Math.max(0,k+8)*1.7;
    if(shape==='spike') p = p0 + (Math.abs(k)<4 ? -5 : 0);
    t = t0 + Math.sin(i/3.1)*(rnd()*9);
    h = Math.max(5, Math.min(100, h0 + Math.sin(i/4.7)*(rnd()*22)));
    pressure.push(Math.round(p*10)/10);
    temp.push(Math.round(t*10)/10);
    humidity.push(Math.round(h*10)/10);
  }
  const d={times,pressure,temp,humidity,nowIndex:n,utcOffset:OFFSET};
  const a=computeAlarm(d);
  cases.push({ times, pressure, temp, humidity, nowIndex:n, utcOffset:OFFSET,
               expect:{ risk:a.risk, level:a.level, word:a.word, note:a.note } });
}
Date.now = realNow;
const out=require('path').join(__dirname,'..','Tests','Fixtures','judgement.json');
fs.mkdirSync(require('path').dirname(out),{recursive:true});
fs.writeFileSync(out, JSON.stringify({ generatedFrom:'widget/index.html', fakeNowEpochMs:FAKE, cases }, null, 1));
const dist={}; cases.forEach(c=>dist[c.expect.risk]=(dist[c.expect.risk]||0)+1);
console.log('書き出し:', cases.length, '件');
console.log('危険度の分布:', JSON.stringify(dist));
console.log('段階の分布:', JSON.stringify(cases.reduce((m,c)=>(m[c.expect.level]=(m[c.expect.level]||0)+1,m),{})));
