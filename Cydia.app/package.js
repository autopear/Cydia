/*var package = {
    "name": "MobileTerminal",
    "latest": "286u-5",
    "author": {
        "name": "Allen Porter",
        "address": "allen.porter@gmail.com"
    },
    //"depiction": "http://planet-iphones.com/repository/info/chromium1.3.php",
    "depiction": "http://cydia.saurik.com/terminal.html",
    "description": "this is a sample description",
    "homepage": "http://cydia.saurik.com/terminal.html",
    "installed": "286u-4",
    "id": "mobileterminal",
    "section": "Terminal Support",
    "size": 552*1024,
    "maintainer": {
        "name": "Jay Freeman",
        "address": "saurik@saurik.com"
    },
    "source": {
        "name": "Telesphoreo Tangelo",
        "description": "Distribution of Unix Software for the iPhone"
    }
};*/

$(function () {
    var id = package.id;
    var name = package.name;
    var regarding = encodeURIComponent("Cydia/APT: " + name);

    $("#name").html(name);
    $("#latest").html(package.latest);

    var author = package.author;
    if (author == null)
        $(".author").remove();
    else {
        $("#author").html(author.name);
        $("#author-href").href("mailto:" + author.address + "?subject=" + regarding);
    }

    $("#notice-src").src("http://apt.saurik.com/notice/" + encodeURIComponent(id) + ".html");

    var depiction = package.depiction;
    if (depiction == null)
        $(".depiction").remove();
    else {
        $(".description").display("none");
        $("#depiction-src").src(depiction);
    }

    var description = package.description;
    if (description == null)
        description = package.tagline;
    else
        description = description.replace(/\n/g, "<br/>");
    $("#description").html(description);

    var homepage = package.homepage;
    if (homepage == null)
        $(".homepage").remove();
    else
        $("#homepage-href").href(homepage);

    var installed = package.installed;
    if (installed == null)
        $(".installed").remove();
    else {
        $("#installed").html(installed);
        $("#files-href").href("cydia://files/" + id);
    }

    $("#id").html(id);

    var section = package.section;
    if (section == null)
        $(".section").remove();
    else
        $("#section").html(package.section);

    var size = package.size;
    if (size == 0)
        $(".size").remove();
    else
        $("#size").html(size / 1024 + " kB");

    var maintainer = package.maintainer;
    if (maintainer == null)
        $(".maintainer").remove();
    else {
        $("#maintainer").html(maintainer.name);
        $("#maintainer-href").href("mailto:" + maintainer.address + "?subject=" + regarding);
    }

    var sponsor = package.sponsor;
    if (sponsor == null)
        $(".sponsor").remove();
    else {
        $("#sponsor").html(sponsor.name);
        $("#sponsor-href").href(sponsor.address);
    }

    var source = package.source;
    if (source == null) {
        $(".source").remove();
        $(".trusted").remove();
    } else {
        $("#source-name").html(source.name);

        if (!source.trusted)
            $(".trusted").remove();

        var description = source.description;
        if (description == null)
            $(".source-description").remove();
        else
            $("#source-description").html(description);
    }
});
