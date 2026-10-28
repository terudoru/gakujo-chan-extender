import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const source = await readFile(process.argv[2], 'utf8');
const ticks = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };
let readers = 0, aborted = 0, workers = 0, activeViewers = 0, currentReader, lastViewer, lastOptions;
const timers = new Map(), intervals = new Map(); let timerId = 0;
class Element {
  constructor(tag, doc) { this.tagName=tag; this.ownerDocument=doc; this.children=[]; this.style={}; this.listeners={}; this.attributes={}; this.isConnected=true; }
  append(...children) { children.forEach(child => this.appendChild(child)); }
  appendChild(child) { this.children.push(child); child.parentNode=this; return child; }
  insertBefore(child) { return this.appendChild(child); }
  after(child) { this.parentNode.appendChild(child); }
  attachShadow() { return new Element('shadow', this.ownerDocument); }
  remove() { this.isConnected=false; if(this.parentNode) this.parentNode.children=this.parentNode.children.filter(x=>x!==this); }
  setAttribute(name,value) { this.attributes[name]=value; }
  addEventListener(name,fn) { (this.listeners[name] ||= []).push(fn); }
  removeEventListener(name,fn) { this.listeners[name]=(this.listeners[name]||[]).filter(x=>x!==fn); }
  fire(name, extra={}) { for(const fn of [...(this.listeners[name]||[])]) fn({target:this,...extra}); }
  focus() {}
  getBoundingClientRect() { return {left:0, top:0}; }
}
const doc={createElement:tag=>new Element(tag,doc)}; doc.body=new Element('body',doc);
const parent=new Element('div',doc);doc.body.appendChild(parent);
const file={name:'synthetic.pdf',type:'application/pdf',size:64};
const inputs=[new Element('input',doc),new Element('input',doc)];
for(const input of inputs){input.files=[file];parent.appendChild(input);}
doc.querySelectorAll=selector=>selector==='input[type="file"]'?inputs:[];
const windowListeners={};
const viewportListeners=new Set();
const window={document:doc,location:{origin:'https://example.invalid'},
 visualViewport:{scale:0.4,addEventListener(name,fn){viewportListeners.add(fn);},removeEventListener(name,fn){viewportListeners.delete(fn);}},
 setTimeout(fn){const id=++timerId;timers.set(id,()=>{timers.delete(id);fn();});return id;},clearTimeout(id){timers.delete(id);},
 setInterval(fn){const id=++timerId;intervals.set(id,fn);return id;},clearInterval(id){intervals.delete(id);},
 addEventListener(name,fn){(windowListeners[name] ||= []).push(fn);},removeEventListener(name,fn){windowListeners[name]=(windowListeners[name]||[]).filter(x=>x!==fn);},
 requestAnimationFrame(fn){fn();return 1;},cancelAnimationFrame(){},
 __MBG_PDF_WORKER_URL:'blob:synthetic',__MBG_PDF_VIEWER_CSS:'synthetic',__MBG_PDF_CMAPS:{synthetic:'AQI='},__MBG_PDF_STANDARD_FONTS:{'sample.pfb':'AQI='}};
window.top=window;doc.defaultView=window;
class FileReader {
 readAsArrayBuffer(){readers++;currentReader=this;}
 abort(){if(this.done)return;this.done=true;readers--;aborted++;this.onabort();}
 finish(){if(this.done)return;this.done=true;readers--;this.result=new ArrayBuffer(4);this.onload();}
}
class Worker {constructor(){workers++;}terminate(){workers--;}}
class EventBus {
 constructor(){this.handlers={};this.findEvents=[];}
 on(name,fn){(this.handlers[name] ||= []).push(fn);}
 dispatch(name,data){if(name==='find')this.findEvents.push(data);for(const fn of this.handlers[name]||[])fn(data);}
}
class PDFLinkService {constructor(){this.externalLinkEnabled=true;}setViewer(v){this.viewer=v;}setDocument(){}}
class PDFFindController {setDocument(){}}
class PDFViewer {
 constructor(options){this.options=options;this.events=options.eventBus;this.page=1;this.currentScale=1;lastViewer=this;}
 get currentPageNumber(){return this.page;}
 set currentPageNumber(page){this.page=page;this.events.dispatch('pagechanging',{pageNumber:page});}
 setDocument(pdf){if(pdf){activeViewers++;this.events.dispatch('pagesinit',{});this.events.dispatch('pagerendered',{});}else if(!this.closed){this.closed=true;activeViewers--;}}
}
const pdf={numPages:3};
window.pdfjsViewer={EventBus,PDFLinkService,PDFFindController,PDFViewer};
window.pdfjsLib={AnnotationMode:{ENABLE:1},PDFWorker:{fromPort:()=>({})},
 getDocument(options){lastOptions=options;return {promise:Promise.resolve(pdf),destroy:()=>Promise.resolve()};}};
const context={window,document:doc,FileReader,Worker,URL:{revokeObjectURL(){}},atob,
 Promise,ArrayBuffer,Uint8Array,DataView,Math,Number,Error};
vm.runInNewContext(source,context);
const controls=parent.children.filter(node=>node.tagName==='button');assert.equal(controls.length,2);
controls[0].fire('click');await ticks();assert.equal(readers,1);
controls[1].fire('click');await ticks();assert.equal(aborted,1);assert.equal(readers,1);
assert.equal(doc.body.children.filter(x=>x.attributes.role==='dialog').length,1);
currentReader.finish();await ticks();assert.equal(workers,1);assert.equal(activeViewers,1);
assert.equal(lastOptions.isEvalSupported,false);assert.equal(lastOptions.enableXfa,false);assert.equal(lastOptions.useWorkerFetch,false);
assert.equal(lastViewer.options.linkService.externalLinkEnabled,false);assert.equal(lastViewer.options.maxCanvasPixels,2000000);
assert.deepEqual([...((await new lastOptions.CMapReaderFactory().fetch({name:'synthetic'})).cMapData)],[1,2]);
assert.deepEqual([...(await new lastOptions.StandardFontDataFactory().fetch({filename:'sample.pfb'}))],[1,2]);
await assert.rejects(new lastOptions.CMapReaderFactory().fetch({name:'../unsafe'}));
const overlay=doc.body.children.find(x=>x.attributes.role==='dialog');const bar=overlay.children[0];
assert.equal(bar.style.zoom,'2.5','toolbar must stay usable on a scaled mobile viewport');
bar.children.find(x=>x.textContent==='次へ').fire('click');assert.equal(lastViewer.currentPageNumber,2);
const area=lastViewer.options.container;
area.scrollLeft=0;area.scrollTop=0;
area.fire('touchstart',{touches:[{clientX:250,clientY:100}]});
area.fire('touchend',{touches:[],changedTouches:[{clientX:100,clientY:105}]});
assert.equal(lastViewer.currentPageNumber,3,'horizontal swipe advances the page');
area.fire('touchstart',{touches:[{clientX:100,clientY:100}]});
area.fire('touchend',{touches:[],changedTouches:[{clientX:110,clientY:250}]});
assert.equal(lastViewer.currentPageNumber,3,'vertical scrolling must not turn the page');
area.fire('wheel',{ctrlKey:true,deltaY:-20,clientX:100,clientY:100,cancelable:true,preventDefault(){}});
assert.ok(lastViewer.currentScale>1,'trackpad zoom changes scale');
const beforePinch=lastViewer.currentScale;
area.fire('touchstart',{touches:[{clientX:100,clientY:100},{clientX:200,clientY:100}]});
area.fire('touchmove',{touches:[{clientX:50,clientY:100},{clientX:250,clientY:100}],cancelable:true,preventDefault(){}});
area.fire('touchend',{touches:[],changedTouches:[{clientX:250,clientY:100}]});
assert.ok(lastViewer.currentScale>beforePinch,'pinch expands the page');
const search=bar.children.find(x=>x.type==='search');search.value='日本語';search.fire('input');
assert.equal(lastViewer.events.findEvents.at(-1).query,'日本語');
bar.children.find(x=>x.textContent==='次の検索結果').fire('click');assert.equal(lastViewer.events.findEvents.at(-1).type,'again');
search.value='العربية';search.fire('input');
lastViewer.events.dispatch('updatefindcontrolstate',{state:1,rawQuery:'العربية'});
assert.equal(lastViewer.events.findEvents.at(-1).query,'ةيبرعلا');
lastViewer.events.dispatch('updatefindcontrolstate',{state:1,rawQuery:'ةيبرعلا'});
assert.equal(lastViewer.events.findEvents.at(-1).query,'العربیة');
inputs[1].fire('change');await ticks();assert.equal(workers,0);assert.equal(activeViewers,0);assert.equal(timers.size,0);assert.equal(viewportListeners.size,0);
delete window.pdfjsLib;window.MbgUploadCompression={postMessage(){}};
for(let i=0;i<10;i++){controls[0].fire('click');await ticks();inputs[0].fire('change');await ticks();}
assert.equal(timers.size,0);assert.equal(workers,0);
window.pdfjsLib={AnnotationMode:{ENABLE:1},PDFWorker:{fromPort:()=>({})},getDocument:()=>({promise:Promise.resolve(pdf),destroy:()=>Promise.resolve()})};
controls[0].fire('click');await ticks();assert.equal(readers,1);assert.equal(timers.size,1);
[...timers.values()][0]();await ticks();assert.equal(readers,0);assert.equal(workers,0);
inputs[0].fire('change');assert.equal(timers.size,0);
inputs[0].files=[file,{...file,name:'second.pdf'}];controls[0].fire('click');
const list=parent.children.find(node=>node.tagName==='div');assert.equal(list.children.length,2);
list.children[1].fire('click');await ticks();assert.equal(readers,1);inputs[0].fire('change');assert.equal(readers,0);
assert.equal(workers,0);assert.equal(activeViewers,0);
console.log('Preview cancellation, PDF viewer lifecycle, search and local font loading are bounded.');
