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
    var idc = encodeURIComponent(id);
    var name = package.name;
    var regarding = encodeURIComponent("Cydia/APT: " + name);

    $("#icon").src("cydia://package-icon/" + idc);
    $("#name").html(name);
    $("#latest").html(package.latest);

    var warnings = package.warnings;
    var length = warnings == null ? 0 : warnings.length;
    if (length == 0)
        $(".warnings").remove();
    else {
        var parent = $("#warnings");
        var child = $("#warning");
        child.remove();

        for (var i = 0; i != length; ++i) {
            var clone = child.clone(true);
            parent.append(clone);
            clone.xpath("label").html($.xml(warnings[i]));
        }
    }

    var applications = package.applications;
    var length = applications == null ? 0 : applications.length;
    if (length == 0)
        $(".applications").remove();
    else {
        var parent = $("#actions");
        var child = $("#application");
        child.remove();

        for (var i = 0; i != length; ++i) {
            var application = applications[i];
            var clone = child.clone(true);
            parent.append(clone);
            clone.href("cydia://launch/" + application[0]);
            clone.xpath("label").html("Run " + $.xml(application[1]));
            clone.xpath("img").src(application[2]);
            console.log(0);
        }
    }

    var author = package.author;
    if (author == null)
        $(".author").remove();
    else {
        $("#author").html(author.name);
        if (author.address == null)
            $("#author-icon").remove();
        else
            $("#author-href").href("mailto:" + author.address + "?subject=" + regarding);
    }

    //$("#notice-src").src("http://saurik.cachefly.net/notice/" + idc + ".html");

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
        $("#files-href").href("cydia://files/" + idc);
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
        if (maintainer.address == null)
            $("#maintainer-icon").remove();
        else
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

        if (source.trusted)
            /*$("#trusted").href("cydia:///" + idc)*/;
        else
            $(".trusted").remove();

        var description = source.description;
        if (description == null)
            $(".source-description").remove();
        else
            $("#source-description").html(description);
    }
});
