const vm: any=require('node:vm'), readline: any=require('node:readline');
const [start,poll,cleanup]: any=process.argv.slice(2);
const length=8*1024*1024+13;
const context: any=vm.createContext({
  location:{origin:'https://gakujo.iess.niigata-u.ac.jp'},
  window:{location:{href:'https://gakujo.iess.niigata-u.ac.jp/'}},
  URL, URLSearchParams, Uint8Array, AbortController,
  fetch:async url=>({url,ok:true,status:200,headers:{get:()=>''},
    body:{getReader(){let offset=0;return {
      async read(){
        if(offset===length)return {done:true};
        const bytes: any=new Uint8Array(Math.min(65537,length-offset));
        for(let i=0;i<bytes.length;i++)bytes[i]=(offset+i)%251;
        offset+=bytes.length;return {value:bytes,done:false};
      },releaseLock(){}
    };}}
  }),btoa:binary=>Buffer.from(binary,'binary').toString('base64')
});
readline.createInterface({input:process.stdin}).on('line',command=>{
  const script={start,poll,cleanup}[command];
  process.stdout.write(String(vm.runInContext(script,context))+'\n');
});

