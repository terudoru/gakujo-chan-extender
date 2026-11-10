import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const source: any = await readFile(process.argv[2], 'utf8');
const ticks: any = async () => { for (let i: any = 0; i < 8; i++) await Promise.resolve(); };
let readers: any = 0, aborted: any = 0, workers: any = 0, activeViewers: any = 0, currentReader, lastViewer, lastOptions;
const timers: any = new Map(), intervals: any = new Map(); let timerId: any = 0;
class Element {
  [key: string]: any;
  constructor(tag: any, doc: any) { this.tagName=tag; this.ownerDocument=doc; this.children=[]; this.style={}; this.listeners={}; this.attributes={}; this.isConnected=true; if(tag==='iframe') this.contentWindow={messages:[],postMessage(...args: any[]){this.messages.push(args);}}; }
  append(...children: any[]) { children.forEach((child: any) => this.appendChild(child)); }
  appendChild(child: any) { this.children.push(child); child.parentNode=this; return child; }
  insertBefore(child: any) { return this.appendChild(child); }
  after(child: any) { this.parentNode.appendChild(child); }
  attachShadow() { return new Element('shadow', this.ownerDocument); }
  remove() { this.isConnected=false; if(this.parentNode) this.parentNode.children=this.parentNode.children.filter((x: any) =>x!==this); }
  setAttribute(name: any,value: any) { this.attributes[name]=value; }
  addEventListener(name: any,fn: any) { (this.listeners[name] ||= []).push(fn); }
  removeEventListener(name: any,fn: any) { this.listeners[name]=(this.listeners[name]||[]).filter((x: any) =>x!==fn); }
  fire(name: any, extra: any={}) { for(const fn of [...(this.listeners[name]||[])]) fn({target:this,...extra}); }
  focus() {}
  getBoundingClientRect() { return {left:0, top:0}; }
}
const doc: any={createElement:(tag: any) =>new Element(tag,doc)}; doc.body=new Element('body',doc);
const parent: any=new Element('div',doc);doc.body.appendChild(parent);
const file: any={name:'synthetic.pdf',type:'application/pdf',size:64};
const inputs: any=[new Element('input',doc),new Element('input',doc)];
for(const input of inputs){input.files=[file];parent.appendChild(input);}
doc.querySelectorAll=(selector: any) =>selector==='input[type="file"]'?inputs:[];
const windowListeners: any={};
const viewportListeners: any=new Set();
const window: any={document:doc,location:{origin:'https://example.invalid'},
 visualViewport:{scale:0.4,width:320,height:500,offsetLeft:95,offsetTop:12,addEventListener(name: any,fn: any){viewportListeners.add(fn);},removeEventListener(name: any,fn: any){viewportListeners.delete(fn);}},
 setTimeout(fn: any){const id: any=++timerId;timers.set(id,()=>{timers.delete(id);fn();});return id;},clearTimeout(id: any){timers.delete(id);},
 setInterval(fn: any){const id: any=++timerId;intervals.set(id,fn);return id;},clearInterval(id: any){intervals.delete(id);},
 addEventListener(name: any,fn: any){(windowListeners[name] ||= []).push(fn);},removeEventListener(name: any,fn: any){windowListeners[name]=(windowListeners[name]||[]).filter((x: any) =>x!==fn);},
 requestAnimationFrame(fn: any){fn();return 1;},cancelAnimationFrame(){},
 __MBG_PDF_WORKER_URL:'blob:synthetic',__MBG_PDF_VIEWER_CSS:'synthetic',__MBG_PDF_CMAPS:{synthetic:'AQI='},__MBG_PDF_STANDARD_FONTS:{'sample.pfb':'AQI='}};
window.top=window;doc.defaultView=window;
class FileReader {
  [key: string]: any;
 readAsArrayBuffer(){readers++;currentReader=this;}
 abort(){if(this.done)return;this.done=true;readers--;aborted++;this.onabort();}
 finish(){if(this.done)return;this.done=true;readers--;this.result=new ArrayBuffer(4);this.onload();}
}
class Worker {
  [key: string]: any;constructor(){workers++;}terminate(){workers--;}}
class EventBus {
  [key: string]: any;
 constructor(){this.handlers={};this.findEvents=[];}
 on(name: any,fn: any){(this.handlers[name] ||= []).push(fn);}
 dispatch(name: any,data: any){if(name==='find')this.findEvents.push(data);for(const fn of this.handlers[name]||[])fn(data);}
}
class PDFLinkService {
  [key: string]: any;constructor(){this.externalLinkEnabled=true;}setViewer(v: any){this.viewer=v;}setDocument(){}}
class PDFFindController {
  [key: string]: any;setDocument(){}}
class PDFViewer {
  [key: string]: any;
 constructor(options: any){this.options=options;this.events=options.eventBus;this.page=1;this.currentScale=1;lastViewer=this;}
 get currentPageNumber(){return this.page;}
 set currentPageNumber(page: any){this.page=page;this.events.dispatch('pagechanging',{pageNumber:page});}
 setDocument(pdf: any){if(pdf){activeViewers++;this.events.dispatch('pagesinit',{});this.events.dispatch('pagerendered',{});}else if(!this.closed){this.closed=true;activeViewers--;}}
}
const pdf: any={numPages:3};
window.pdfjsViewer={EventBus,PDFLinkService,PDFFindController,PDFViewer};
window.pdfjsLib={AnnotationMode:{ENABLE:1},PDFWorker:{fromPort:()=>({})},
 getDocument(options: any){lastOptions=options;return {promise:Promise.resolve(pdf),destroy:()=>Promise.resolve()};}};
const context: any={window,document:doc,FileReader,Worker,URL:{revokeObjectURL(){}},atob,
 Promise,ArrayBuffer,Uint8Array,DataView,Math,Number,Error};
vm.runInNewContext(source,context);
const controls: any=parent.children.filter((node: any) =>node.tagName==='button');assert.equal(controls.length,2);
controls[0].fire('click');await ticks();assert.equal(readers,1);
controls[1].fire('click');await ticks();assert.equal(aborted,1);assert.equal(readers,1);
assert.equal(doc.body.children.filter((x: any) =>x.attributes.role==='dialog').length,1);
currentReader.finish();await ticks();assert.equal(workers,1);assert.equal(activeViewers,1);
assert.equal(lastOptions.isEvalSupported,false);assert.equal(lastOptions.enableXfa,false);assert.equal(lastOptions.useWorkerFetch,false);
assert.equal(lastViewer.options.linkService.externalLinkEnabled,false);assert.equal(lastViewer.options.maxCanvasPixels,2000000);
assert.deepEqual([...((await new lastOptions.CMapReaderFactory().fetch({name:'synthetic'})).cMapData)],[1,2]);
assert.deepEqual([...(await new lastOptions.StandardFontDataFactory().fetch({filename:'sample.pfb'}))],[1,2]);
await assert.rejects(new lastOptions.CMapReaderFactory().fetch({name:'../unsafe'}));
const overlay: any=doc.body.children.find((x: any) =>x.attributes.role==='dialog');const bar: any=overlay.children[0];
assert.equal(window.__MBG_PREVIEW_NAVIGATE('back'),true);
assert.equal(overlay.style.display,'none','back reveals the underlying page');
assert.equal(activeViewers,1,'back preserves the viewer');
assert.equal(window.__MBG_PREVIEW_NAVIGATE('back'),false,'a second back can use page history');
assert.equal(window.__MBG_PREVIEW_NAVIGATE('forward'),true);
assert.equal(overlay.style.display,'flex','forward restores the same viewer');
assert.equal(window.__MBG_PREVIEW_NAVIGATE('forward'),true,'forward cannot skip an open preview');
assert.equal(bar.style.zoom,'2.5','toolbar must stay usable on a scaled mobile viewport');
assert.equal(overlay.style.left,'95px');assert.equal(overlay.style.top,'12px');
assert.equal(overlay.style.width,'320px');assert.equal(overlay.style.height,'500px');
window.visualViewport.offsetLeft=20; for(const listener of viewportListeners)listener();
assert.equal(overlay.style.left,'20px','panning updates the visible preview bounds');
bar.children.find((x: any) =>x.textContent==='次へ').fire('click');assert.equal(lastViewer.currentPageNumber,2);
const area: any=lastViewer.options.container;
area.scrollLeft=0;area.scrollTop=0;
area.fire('touchstart',{touches:[{clientX:250,clientY:100}]});
area.fire('touchend',{touches:[],changedTouches:[{clientX:100,clientY:105}]});
assert.equal(lastViewer.currentPageNumber,3,'horizontal swipe advances the page');
area.fire('touchstart',{touches:[{clientX:100,clientY:100}]});
area.fire('touchend',{touches:[],changedTouches:[{clientX:110,clientY:250}]});
assert.equal(lastViewer.currentPageNumber,3,'vertical scrolling must not turn the page');
area.fire('wheel',{ctrlKey:true,deltaY:-20,clientX:100,clientY:100,cancelable:true,preventDefault(){}});
assert.ok(lastViewer.currentScale>1,'trackpad zoom changes scale');
const beforePinch: any=lastViewer.currentScale;
area.fire('touchstart',{touches:[{clientX:100,clientY:100},{clientX:200,clientY:100}]});
area.fire('touchmove',{touches:[{clientX:50,clientY:100},{clientX:250,clientY:100}],cancelable:true,preventDefault(){}});
area.fire('touchend',{touches:[],changedTouches:[{clientX:250,clientY:100}]});
assert.ok(lastViewer.currentScale>beforePinch,'pinch expands the page');
const search: any=bar.children.find((x: any) =>x.type==='search');search.value='日本語';search.fire('input');
assert.equal(lastViewer.events.findEvents.at(-1).query,'日本語');
bar.children.find((x: any) =>x.textContent==='次の検索結果').fire('click');assert.equal(lastViewer.events.findEvents.at(-1).type,'again');
search.value='العربية';search.fire('input');
lastViewer.events.dispatch('updatefindcontrolstate',{state:1,rawQuery:'العربية'});
assert.equal(lastViewer.events.findEvents.at(-1).query,'ةيبرعلا');
lastViewer.events.dispatch('updatefindcontrolstate',{state:1,rawQuery:'ةيبرعلا'});
assert.equal(lastViewer.events.findEvents.at(-1).query,'العربیة');
inputs[1].fire('change');await ticks();assert.equal(workers,0);assert.equal(activeViewers,0);assert.equal(timers.size,0);assert.equal(viewportListeners.size,0);
assert.equal(window.__MBG_PREVIEW_NAVIGATE('forward'),false,'closing discards preview history');
delete window.pdfjsLib;window.MbgUploadCompression={postMessage(){}};
for(let i: any=0;i<10;i++){controls[0].fire('click');await ticks();inputs[0].fire('change');await ticks();}
assert.equal(timers.size,0);assert.equal(workers,0);
window.pdfjsLib={AnnotationMode:{ENABLE:1},PDFWorker:{fromPort:()=>({})},getDocument:()=>({promise:Promise.resolve(pdf),destroy:()=>Promise.resolve()})};
controls[0].fire('click');await ticks();assert.equal(readers,1);assert.equal(timers.size,1);
[...timers.values()][0]();await ticks();assert.equal(readers,0);assert.equal(workers,0);
inputs[0].fire('change');assert.equal(timers.size,0);
inputs[0].files=[file,{...file,name:'second.pdf'}];controls[0].fire('click');
const list: any=parent.children.find((node: any) =>node.tagName==='div');assert.equal(list.children.length,2);
list.children[1].fire('click');await ticks();assert.equal(readers,1);inputs[0].fire('change');assert.equal(readers,0);
assert.equal(workers,0);assert.equal(activeViewers,0);
inputs[0].files=[file];window.__MBG_PDF_PREVIEW_URL='http://127.0.0.1:1234/secret/index.html';
controls[0].fire('click');await ticks();currentReader.finish();await ticks();
const sandboxOverlay: any=doc.body.children.find((x: any) =>x.attributes.role==='dialog');
const iframe: any=sandboxOverlay.children[1].children.find((x: any) =>x.tagName==='iframe');
assert.equal(iframe.attributes.sandbox,'allow-scripts');
assert.equal(iframe.src,window.__MBG_PDF_PREVIEW_URL);
assert.equal(iframe.style.width,'40%','viewer layout uses the physical mobile viewport');
assert.equal(iframe.style.height,'40%');
assert.equal(iframe.style.transform,'scale(2.5)','viewer fills the scaled parent viewport');
window.screen={width:914,height:411};
window.visualViewport.height=350;for(const listener of viewportListeners)listener();
assert.equal(sandboxOverlay.children[0].style.display,'none','Flutter viewer owns the toolbar even with the keyboard open');
window.visualViewport.height=500;for(const listener of viewportListeners)listener();
assert.equal(sandboxOverlay.children[0].style.display,'none','resizing must not restore the HTML header');
delete window.screen;
window.visualViewport.scale=1;for(const listener of viewportListeners)listener();
assert.equal(iframe.style.width,'100%','viewer adapts when page zoom changes');
assert.equal(iframe.style.transform,'scale(1)');
window.visualViewport.scale=0.4;for(const listener of viewportListeners)listener();
for(const fn of windowListeners.message||[])fn({source:{},data:'mbg-preview-ready'});
assert.equal(iframe.contentWindow.messages.length,0,'another frame must not receive the document');
for(const fn of windowListeners.message||[])fn({source:iframe.contentWindow,data:'mbg-preview-ready'});
assert.equal(iframe.contentWindow.messages.length,2);
assert.equal(iframe.contentWindow.messages[0][0].type,'mbg-preview-title');
assert.equal(iframe.contentWindow.messages[0][0].name,file.name);
assert.equal(iframe.contentWindow.messages[1][0].byteLength,4);
assert.equal(iframe.contentWindow.messages[1][2][0],iframe.contentWindow.messages[1][0]);
for(const fn of windowListeners.message||[])fn({source:iframe.contentWindow,data:'mbg-preview-password-requested'});
assert.equal(timers.size,0,'a password prompt must not time out while the user is typing');
for(const fn of windowListeners.message||[])fn({source:iframe.contentWindow,data:'mbg-preview-password-finished'});
assert.equal(timers.size,1,'the watchdog resumes after the password prompt');
for(const fn of windowListeners.message||[])fn({source:iframe.contentWindow,data:'mbg-preview-loaded'});
assert.equal(timers.size,0);
for(const fn of [...(windowListeners.message||[])])fn({source:{},data:'mbg-preview-close'});
assert.equal(iframe.isConnected,true,'another frame cannot close the preview');
for(const fn of [...(windowListeners.message||[])])fn({source:iframe.contentWindow,data:'mbg-preview-close'});
assert.equal((windowListeners.message||[]).length,0,'closing removes the message listener');
assert.equal(iframe.isConnected,false);
const popup: any={messages:[],closed:false,postMessage(...args: any[]){this.messages.push(args);},close(){this.closed=true;}};
window.__MBG_PDF_PREVIEW_POPUP=true;
window.open=(url: any,target: any)=>{assert.equal(url,window.__MBG_PDF_PREVIEW_URL);assert.equal(target,'_blank');return popup;};
controls[0].fire('click');await ticks();currentReader.finish();await ticks();
for(const fn of windowListeners.message||[])fn({source:{},data:'mbg-preview-ready'});
assert.equal(popup.messages.length,0,'unrelated windows cannot receive the PDF');
for(const fn of windowListeners.message||[])fn({source:popup,data:'mbg-preview-ready'});
assert.equal(popup.messages.length,2);
assert.equal(popup.messages[0][0].type,'mbg-preview-title');
assert.equal(popup.messages[0][0].name,file.name);
assert.equal(popup.messages[1][0].byteLength,4);
for(const fn of windowListeners.message||[])fn({source:popup,data:'mbg-preview-loaded'});
assert.equal(timers.size,0);
const popupOverlay: any=doc.body.children.find((x: any) =>x.attributes.role==='dialog');
assert.equal(popupOverlay.children[0].style.display,'none');
assert.equal(popupOverlay.children[1].children[0].textContent,'');
for(const fn of [...(windowListeners.message||[])])fn({source:popup,data:'mbg-preview-close'});
assert.equal(popup.closed,true,'closing the preview also closes its window');
assert.equal((windowListeners.message||[]).length,0);
window.__MBG_PDF_PREVIEW_POPUP=false;
controls[0].fire('click');await ticks();currentReader.finish();await ticks();
const failedOverlay: any=doc.body.children.find((x: any) =>x.attributes.role==='dialog');
const failedFrame: any=failedOverlay.children[1].children.find((x: any) =>x.tagName==='iframe');
for(const fn of [...(windowListeners.message||[])])fn({source:failedFrame.contentWindow,data:'mbg-preview-failed'});
assert.equal(failedOverlay.children[0].style.display,'flex','failure restores the close bar');
assert.match(failedOverlay.children[1].children[0].textContent,/プレビューできません/);
const closeButton: any=failedOverlay.children[0].children.at(-1);
assert.equal(closeButton.textContent,'×');assert.equal(closeButton.attributes['aria-label'],'閉じる');
closeButton.fire('click');
const childDoc: any={createElement:(tag: any) =>new Element(tag,childDoc)};
childDoc.body=new Element('body',childDoc);
const childInput: any=new Element('input',childDoc);childInput.files=[file];childDoc.body.appendChild(childInput);
childDoc.querySelectorAll=(selector: any) =>selector==='input[type="file"]'?[childInput]:[];
const childViewport: any={scale:1,width:180,height:240,offsetLeft:7,offsetTop:9,addEventListener(){},removeEventListener(){}};
const childWindow: any={document:childDoc,visualViewport:childViewport,frameElement:{isConnected:true},addEventListener(){},removeEventListener(){}};
childDoc.defaultView=childWindow;
const previousQuery: any=doc.querySelectorAll;
doc.querySelectorAll=(selector: any) =>selector==='iframe,frame'?[{contentWindow:childWindow}]:previousQuery(selector);
for(const tick of [...intervals.values()])tick();
childInput.__mbgPreviewButton.fire('click');await ticks();
const childOverlay: any=childDoc.body.children.find((x: any) =>x.attributes.role==='dialog');
assert.equal(childOverlay.style.width,'180px','an iframe uses its own visual viewport');
assert.equal(childOverlay.style.left,'7px');
assert.equal(childOverlay.children[0].style.zoom,'2.5','an iframe inherits the scaled top-level viewport');
window.visualViewport.scale=1;for(const listener of viewportListeners)listener();
assert.equal(childOverlay.children[0].style.zoom,'1','an iframe follows top-level scale changes');
childWindow.frameElement.offsetWidth=400;
childWindow.frameElement.getBoundingClientRect=()=>({width:200});
for(const listener of viewportListeners)listener();
assert.equal(childOverlay.children[0].style.zoom,'2','CSS-scaled frames also retain usable controls');
childInput.fire('change');await ticks();
console.log('Preview cancellation, PDF viewer lifecycle, search and local font loading are bounded.');
