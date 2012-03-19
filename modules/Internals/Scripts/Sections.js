function showContent(header, id)
{
    e = document.getElementById(id);
    if(e.style.display == 'none')
    {
        e.style.display = 'block';
        e.style.visibility = 'visible';
        header.innerHTML = header.innerHTML.replace(/\[[^0-9 ]\]/gi,"[&minus;]");
    }
    else
    {
        e.style.display = 'none';
        e.style.visibility = 'hidden';
        header.innerHTML = header.innerHTML.replace(/\[[^0-9 ]\]/gi,"[+]");
    }
}