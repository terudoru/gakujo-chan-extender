import {mbgValidateImage} from '../../web_scripts/src/shared/image_bounds.ts';
const png = [137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,10,0,0,0,20,
  8,2,0,0,0,0,0,0,0,0,0,0,0,73,68,65,84,0,0,0,0];
const jpeg = [255,216,255,192,0,8,8,0,20,0,10,1];
const webp = [82,73,70,70,0,0,0,0,87,69,66,80,86,80,56,88,0,0,0,0,0,0,0,0,9,0,0,19,0,0];
(async () => {
  for (const bytes of [png, jpeg, webp]) {
    const size = await mbgValidateImage(new Blob([Uint8Array.from(bytes)]));
    if (size.width !== 10 || size.height !== 20) throw Error('valid dimensions');
  }
  const huge: any = png.slice(); huge[16]=0; huge[17]=0; huge[18]=39; huge[19]=17;
  const apng: any = png.slice(0,33).concat([0,0,0,0,97,99,84,76,0,0,0,0], png.slice(33));
  const animatedWebp: any = webp.slice(); animatedWebp[20] = 2;
  for (const bytes of [huge, apng, animatedWebp, [1,2,3]]) {
    let rejected: any = false;
    try { await mbgValidateImage(new Blob([Uint8Array.from(bytes)])); } catch (_) { rejected = true; }
    if (!rejected) throw Error('unsafe header accepted');
  }
})().catch((e: any) => { console.error(e); process.exit(1); });
