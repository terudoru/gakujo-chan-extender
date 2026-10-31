export {};
function calendarRegistrationPageFetch(): string {
  function get(url: string) {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, false);
    xhr.send(null);
    return xhr.status >= 200 && xhr.status < 400 ? xhr.responseText : '';
  }
  try {
    var first = get('/campusweb/campussquare.do?_flowId=RSW0001000-flow');
    var pages = [first];
    var links = first.match(/href="[^"]*_eventId=search(?:&amp;|&)gakkiKbnCode=[0-9]+"/g) || [];
    for (var i = 0; i < links.length; i += 1) {
      pages.push(get(links[i].slice(6, -1).replace(/&amp;/g, '&')));
    }
    return JSON.stringify({status: first ? 200 : 0, text: pages.join('\n')});
  } catch (e) {
    return JSON.stringify({status: 0, text: ''});
  }
}

__mbgEntryResult = calendarRegistrationPageFetch();
