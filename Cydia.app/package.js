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
        node.css("letter-spacing", spacing);
    }
}

function cache(url) {
    return url.replace('://', '://ne.edgecastcdn.net/8003A4/');
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

var special_ = function () {
    if (package == null)
        return;

    var id = package.id;
    var idc = encodeURIComponent(id);
    var name = package.name;
    var icon = 'cydia://package-icon/' + idc;
    var api = 'http://cydia.saurik.com/api/';

    var regarding = function (type) {
        return encodeURIComponent("Cydia/APT(" + type + "): " + name);
    };

    $("#icon").css("background-image", 'url("' + icon + '")');
    //$("#reflection").src("cydia://package-icon/" + idc);

    $("#name").html(name);
    space("#latest", package.latest, 96);

    $.xhr(cache(api + 'package/' + idc), 'GET', {}, null, {
        success: function (value) {
            value = eval(value);

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

    $("#settings").href("cydia://package-settings/" + idc);

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
        space("#author", author.name, 160);
        if (author.address == null)
            $("#author-icon").addClass("deleted");
        else {
            var support = package.support;
            if (support == null)
                $("#author-href").href("mailto:" + author.address + "?subject=" + regarding("A"));
            else
                $("#author-href").href(support);
        }
    }

    //$("#notice-src").src("http://saurik.cachefly.net/notice/" + idc + ".html");

    /*var store = commercial;
    if (!store)
        $(".activation").addClass("deleted");
    else {
        var activation = api + 'activation/' + idc;
        $("#activation-src").src(activation);
    }*/

    var depiction = package.depiction;
    if (depiction == null)
        $(".depiction").addClass("deleted");
    else {
        $(".description").addClass("deleted");
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
        $(".homepage").addClass("deleted");
    else
        $("#homepage-href").href(homepage);

    var installed = package.installed;
    if (installed == null)
        $(".installed").addClass("deleted");
    else {
        $("#installed").html(installed);
        $("#files-href").href("cydia://files/" + idc);
    }

    space("#id", id, 220);

    var section = package.section;
    if (section == null)
        $(".section").addClass("deleted");
    else {
        $("#section-src").src("cydia://section-icon/" + encodeURIComponent(section));
        $("#section").html(section);
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
        space("#maintainer", maintainer.name, 153);
        if (maintainer.address == null)
            $("#maintainer-icon").addClass("deleted");
        else
            $("#maintainer-href").href("mailto:" + maintainer.address + "?subject=" + regarding("M"));
    }

    var sponsor = package.sponsor;
    if (sponsor == null)
        $(".sponsor").addClass("deleted");
    else {
        space("#sponsor", sponsor.name, 152);
        $("#sponsor-href").href(sponsor.address);
    }

    var source = package.source;
    if (source == null) {
        $(".source").addClass("deleted");
        $(".trusted").addClass("deleted");
    } else {
        var host = source.host;

        $("#source-src").src("cydia://source-icon/" + encodeURIComponent(host));
        $("#source-name").html(source.name);

        if (source.trusted)
            $("#trusted").href("cydia://package-signature/" + idc);
        else
            $(".trusted").addClass("deleted");

        var description = source.description;
        if (description == null)
            $(".source-description").addClass("deleted");
        else
            $("#source-description").html(description);
    }
};

$(special_);

var special = function () {
    $(".deleted").removeClass("deleted");
    $(".inserted").remove();

    $("#icon")[0].className = 'flip-0';
    $("#thumb")[0].className = 'flip-180';

    /* XXX: this could be better */
    $("#rating-none").css("display", "none");
    $("#rating-done").css("display", "none");

    var depiction = $("#depiction-src");

    depiction[0].outerHTML = '<iframe' +
        ' class="depiction"' +
        ' id="depiction-src"' +
        ' frameborder="0"' +
        ' width="320"' +
        ' height="0"' +
        ' target="_top"' +
        ' onload_="loaded()"' +
    '></iframe>';

    special_();
};

cydia.setSpecial(special);
