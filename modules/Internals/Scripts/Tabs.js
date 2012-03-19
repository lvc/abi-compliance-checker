function initTabs()
{
    var url = window.location.href;
    if(url.indexOf('_Source_')!=-1 || url.indexOf('#Source')!=-1)
    {
        var tab1 = document.getElementById('BinaryID');
        var tab2 = document.getElementById('SourceID');
        tab1.className='tab disabled';
        tab2.className='tab active';
    }
    var sets = document.getElementsByTagName('div');
    for (var i = 0; i < sets.length; i++)
    {
        if (sets[i].className.indexOf('tabset') != -1)
        {
            var tabs = [];
            var links = sets[i].getElementsByTagName('a');
            for (var j = 0; j < links.length; j++)
            {
                if (links[j].className.indexOf('tab') != -1)
                {
                    tabs.push(links[j]);
                    links[j].tabs = tabs;
                    var tab = document.getElementById(links[j].href.substr(links[j].href.indexOf('#') + 1));
                    //reset all tabs on start
                    if (tab)
                    {
                        if (links[j].className.indexOf('active')!=-1) {
                            tab.style.display = 'block';
                        }
                        else {
                            tab.style.display = 'none';
                        }
                    }
                    links[j].onclick = function()
                    {
                        var tab = document.getElementById(this.href.substr(this.href.indexOf('#') + 1));
                        if (tab)
                        {
                            //reset all tabs before change
                            for (var k = 0; k < this.tabs.length; k++)
                            {
                                document.getElementById(this.tabs[k].href.substr(this.tabs[k].href.indexOf('#') + 1)).style.display = 'none';
                                this.tabs[k].className = this.tabs[k].className.replace('active', 'disabled');
                            }
                            this.className = 'tab active';
                            tab.style.display = 'block';
                            // window.location.hash = this.id.replace('ID', '');
                            return false;
                        }
                    }
                }
            }
        }
    }
    if(url.indexOf('#')!=-1) {
        location.href=location.href;
    }
}
if (window.addEventListener) window.addEventListener('load', initTabs, false);
else if (window.attachEvent) window.attachEvent('onload', initTabs);