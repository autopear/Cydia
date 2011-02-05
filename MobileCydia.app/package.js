/*var package = {
    "name": "MobileTerminal",
    "latest": "286u-5",
    "author": {
        "name": "Allen Porter",
        "address": "allen.porter@gmail.com"
    },
    //"depiction": "http://planet-iphones.com/repository/info/chromium1.3.php",
    "depiction": "http://cydia.saurik.com/terminal.html",
    "longDescription": "this is a sample description",
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
        node.css("letter-spacing", spacing);
    }
}

var swap_, swap = function (on, off, time) {
    setTimeout(swap_(on, off, time), time);
};

swap_ = function (on, off, time) {
    return function () {
        on.className = 'fade-out';
        off.className = 'fade-in';
        swap(off, on, time);
    };
};

$(function () {
    if (package == null)
        return;

    var id = package.id;
    var idc = encodeURIComponent(id);
    var name = package.name;
    var icon = 'cydia://package-icon/' + idc;

    var api = 'http://cydia.saurik.com/api/';
    var capi = 'http://cache.cydia.saurik.com/api/';

    var support = package.support;

    var regarding = function (type) {
        return encodeURIComponent("Cydia/APT(" + type + "): " + name);
    };

    $("#icon").css("background-image", 'url("' + icon + '")');
    //$("#reflection").src("cydia://package-icon/" + idc);

    $("#name").html($.xml(name));
    space("#latest", $.xml(package.latest), 96);

    $.xhr(capi + 'package/' + idc, 'GET', {}, null, {
        success: function (value) {
            value = eval(value);

            if (typeof value.notice == "undefined")
                $(".notice").addClass("deleted");
            else
                $("#notice-src").src(value.notice);

            if (typeof value.rating == "undefined")
                $(".rating").addClass("deleted");
            else {
                $("#rating-load").addClass("deleted");
                $("#rating-href").href(value.reviews);

                var none = $("#rating-none");
                var done = $("#rating-done");

                if (value.rating == null) {
                    none.css("display", "block");
                } else {
                    done.css("display", "block");

                    $("#rating-value").css('width', 16 * value.rating);
                }
            }

            if (typeof value.icon != "undefined" && value.icon != null) {
                var icon = $("#icon");
                var thumb = $("#thumb");

                icon[0].className = 'flip-180';
                thumb[0].className = 'flip-360';

                thumb.css("background-image", 'url("' + value.icon + '")');

                setTimeout(function () {
                    icon.addClass("deleted");
                    thumb[0].className = 'flip-0';
                }, 2000);
            }
        },

        failure: function (status) {
            $(".rating").addClass("deleted");
        }
    });

    $("#settings").href("cydia://package/" + idc + "/settings");

    var mode = package.mode;
    if (mode == null)
        $(".mode").addClass("deleted");
    else {
        $("#mode").html(cydia.localize(mode));
        $("#mode-src").src("Modes/" + mode + ".png");
    }

    var warnings = package.warnings;
    var length = warnings == null ? 0 : warnings.length;
    if (length == 0)
        $(".warnings").addClass("deleted");
    else {
        var parent = $("#warnings");
        var child = $("#warning");

        for (var i = 0; i != length; ++i) {
            var clone = child.clone(true);
            clone.addClass("inserted");
            parent.append(clone);
            clone.xpath("./div/label").html($.xml(warnings[i]));
        }

        child.addClass("deleted");
    }

    var applications = package.applications;
    var length = applications == null ? 0 : applications.length;

    var child = $("#application");

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

    child.addClass("deleted");

    var commercial = package.hasTag('cydia::commercial');
    if (!commercial)
        $(".commercial").addClass("deleted");

    var _console = package.hasTag('purpose::console');
    if (!_console)
        $(".console").addClass("deleted");

    var author = package.author;
    if (author == null)
        $(".author").addClass("deleted");
    else {
        space("#author", $.xml(author.name), 160);
        if (author.address == null)
            $("#author-icon").addClass("deleted");
        else if (support == null)
            $("#author-href").href("mailto:" + author.address + "?subject=" + regarding("A"));
        else
            $("#author-href").href(support);
    }

    /*var store = commercial;
    if (!store)
        $(".activation").addClass("deleted");
    else {
        var activation = api + 'activation/' + idc;
        $("#activation-src").src(activation);
    }*/

    var depiction = package.depiction;
    if (depiction != null) {
        $(".description").addClass("deleted");
        $("#depiction-src").src(depiction);
    } else {
        $(".depiction").addClass("deleted");

        var description = package.longDescription;
        if (description == null)
            description = package.shortDescription;

        if (description == null)
            $(".description").addClass("deleted");
        else {
            description = $.xml(description).replace(/\n/g, "<br/>");
            $("#description").html(description);
        }
    }

    var homepage = package.homepage;
    if (homepage == null)
        $(".homepage").addClass("deleted");
    else
        $("#homepage-href").href(homepage);

    var installed = package.installed;
    if (installed == null)
        $(".installed").addClass("deleted");
    else {
        $("#installed").html($.xml(installed));
        $("#files-href").href("cydia://package/" + idc + "/files");
    }

    space("#id", $.xml(id), 220);

    var section = package.longSection;
    if (section == null)
        $(".section").addClass("deleted");
    else {
        $("#section-src").src("cydia://section-icon/" + encodeURIComponent(section));
        $("#section").html($.xml(section));
    }

    var size = package.size;
    if (size == 0)
        $(".size").addClass("deleted");
    else
        $("#size").html(size / 1024 + " kB");

    var maintainer = package.maintainer;
    if (maintainer == null)
        $(".maintainer").addClass("deleted");
    else {
        space("#maintainer", $.xml(maintainer.name), 153);
        if (maintainer.address == null)
            $("#maintainer-icon").addClass("deleted");
        else if (support == null)
            $("#maintainer-href").href("mailto:" + maintainer.address + "?subject=" + regarding("M"));
        else
            $("#maintainer-href").href(support);
    }

    var sponsor = package.sponsor;
    if (sponsor == null)
        $(".sponsor").addClass("deleted");
    else {
        space("#sponsor", $.xml(sponsor.name), 152);
        $("#sponsor-href").href(sponsor.address);
    }

    var source = package.source;
    if (source == null) {
        $(".source").addClass("deleted");
        $(".trusted").addClass("deleted");
    } else {
        var host = source.host;

        $("#source-src").src("cydia://source-icon/" + encodeURIComponent(host));
        $("#source-name").html($.xml(source.name));

        if (source.trusted)
            $("#trusted").href("cydia://package/" + idc + "/signature");
        else
            $(".trusted").addClass("deleted");

        var description = source.description;
        if (description == null)
            $(".source-description").addClass("deleted");
        else
            $("#source-description").html($.xml(description));
    }

    $("body").removeClass("invisible");
});
