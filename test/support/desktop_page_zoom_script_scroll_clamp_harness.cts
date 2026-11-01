const vm: any = require('node:vm');
const win: any = {frames: [], innerWidth: 900, innerHeight: 700,
  scrollX: 0, scrollY: 3200, __MBG_PAGE_EFFECTIVE_ZOOM: 1.4,
  addEventListener() {}, clearTimeout() {}, setTimeout() {},
  scrollTo(x,y) { this.scrollX=x; this.scrollY=y; }};
if (process.argv[3] === 'first') delete win.__MBG_PAGE_EFFECTIVE_ZOOM;
const style: any = new Proxy({}, {set(target,key,value) {
  if (key === 'transform' && value === 'none') win.scrollY=Math.min(win.scrollY,2900);
  target[key]=value; return true;
}});
win.document = {body:{style,scrollWidth:900,offsetWidth:900,scrollHeight:3600,offsetHeight:3600},
  documentElement:{style:{},clientWidth:900,scrollWidth:900,offsetWidth:900,scrollHeight:3600,offsetHeight:3600}};
vm.runInNewContext(process.argv[2], {window:win});
process.stdout.write(JSON.stringify(win.scrollY));

