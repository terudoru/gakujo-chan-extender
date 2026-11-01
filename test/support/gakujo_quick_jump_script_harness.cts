const vm: any = require('node:vm');
const spec: any = JSON.parse(process.argv[2]);
const clicked: any = [];
function windowFor(specs?: any) {
  const element = spec => ({
    ...spec, innerText: spec.text || '', textContent: spec.text || '',
    attributes: Object.keys(spec).map(name => ({name})),
    parentElement: spec.parent ? element(spec.parent) : null,
    getAttribute: name => spec[name] || null,
    matches: selector => selector === ':disabled' && !!spec.disabled,
    closest: () => spec.inert || spec.ariaDisabled ? {} : null,
    getClientRects: () => spec.hidden ? [] : [{}],
    querySelectorAll: () => spec.imageAlt ? [{getAttribute: () => spec.imageAlt}] : [],
    click: spec.noClick ? undefined : () => {
      clicked.push(spec.id);
      if (spec.clickThrows) throw new Error('synthetic click failure');
    },
  });
  const nodes: any = specs.map(element);
  const nodesById = new Map(nodes.map(node => [node.id, node]));
  nodes.forEach(node => {
    if (node.parentId) node.parentElement = nodesById.get(node.parentId) || null;
    node.contains = other => {
      for (let current = other; current; current = current.parentElement) {
        if (current === node) return true;
      }
      return false;
    };
  });
  const win: any = {frames: [], getComputedStyle: node => ({visibility: node.visibility || 'visible'})};
  win.document = {defaultView: win, querySelectorAll: selector => nodes.filter(node =>
    selector.includes('td, div, span') || ['a','button'].includes(node.tag) ||
    selector.includes('div.tabcell') && node.tag === 'div' &&
      (node.class || '').split(/\s+/).includes('tabcell') ||
    node.tag === 'input' && ['button','submit','image'].includes(node.type) ||
    ['tab','button','menuitem'].includes(node.role) || !!node.onclick
  )};
  return win;
}
const window: any = windowFor(spec.nodes);
window.frames = spec.frames.map(windowFor);
const result: any = vm.runInNewContext(process.argv[3], {window});
process.stdout.write(JSON.stringify({result, clicked}));

