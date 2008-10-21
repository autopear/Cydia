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

function space(selector, html, max) {
    var node = $(selector);
    node.html(html);
    var width = node.width();
    if (width > max) {
        var spacing = (max - node.width()) / (html.length - 1) + "px";
        console.log(width + " " + max + " " + spacing);
        node.css("letter-spacing", spacing);
    }
}

$(function () {
    var id = package.id;
    var idc = encodeURIComponent(id);
    var name = package.name;
    var regarding = encodeURIComponent("Cydia/APT: " + name);

    $("#icon").src("cydia://package-icon/" + idc);
    $("#reflection").src("cydia://package-icon/" + idc);

    $("#name").html(name);
    space("#latest", package.latest, 93);

    var rating = package.rating;
    if (rating == null)
        $(".rating").remove();
    else
        $("#rating").src(rating);

    $("#settings").href("cydia://package-settings/" + idc);

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

    var child = $("#application");
    child.remove();

    /*if (length != 0) {
        var parent = $("#actions");

        for (var i = 0; i != length; ++i) {
            var application = applications[i];
            var clone = child.clone(true);
            parent.append(clone);
            clone.href("cydia://launch/" + application[0]);
            clone.xpath("label").html("Run " + $.xml(application[1]));
            clone.xpath("img").src(application[2]);
        }
    }*/

    var purposes = package.purposes;
    var commercial = false;
    var _console = false;
    if (purposes != null)
        for (var i = 0, e = purposes.length; i != e; ++i) {
            var purpose = purposes[i];
            if (purpose == "commercial")
                commercial = true;
            else if (purpose == "console")
                _console = true;
        }
    if (!commercial)
        $(".commercial").remove();
    if (!_console)
        $(".console").remove();

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

    space("#id", id, 238);

    var section = package.section;
    if (section == null)
        $(".section").remove();
    else {
        $("#section-src").src("cydia://section-icon/" + encodeURIComponent(section));
        $("#section").html(section);
    }

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
        var host = source.host;

        $("#source-src").src("cydia://source-icon/" + encodeURIComponent(host));
        $("#source-name").html(source.name);

        if (source.trusted)
            $("#trusted").href("cydia://package-signature/" + idc);
        else
            $(".trusted").remove();

        var description = source.description;
        if (description == null)
            $(".source-description").remove();
        else
            $("#source-description").html(description);
    }
});
