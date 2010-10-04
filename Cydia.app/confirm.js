$(function () {
    if (issues == null) {
        $(".issues").remove();

        var downloading = sizes[0];
        if (downloading == "0.0 B")
            $(".downloading").remove();
        else
        $("#downloading").html($.xml(downloading));

        var resuming = sizes[1];
        if (resuming == "0.0 B")
            $(".resuming").remove();
        else
        $("#resuming").html($.xml(resuming));
    } else for (var i = 0; i != issues.length; ++i) {
        document.title = cydia.localize("CANNOT_COMPLY");

        $(".queue").remove();

        $("._issues").remove();

        var issue = issues[i];

        $("#issues").append(
            "<label style=\"color: #704d4d\">" + $.xml(issue[0]) + "</label>" +
            "<fieldset style=\"background-color: #dddddd\" class=\"clearfix\" id=\"i" + i + "\"></fieldset>"
        );

        for (var j = 1; j != issue.length; ++j) {
            var entry = issue[j];
            var type = entry[0];
            if (type == "PreDepends")
                type = "Depends";
            var version = entry[1];
            if (entry.length >= 4)
                version += " " + entry[3];
            $("#i" + i).append("<div class=\"clearfix\"><div>" +
                "<label>" + $.xml(type) + "</label>" +
                "<label>" + $.xml(version) + "</label>" +
            "</div></div>");
        }
    }

    var keys = [
        "INSTALL",
        "REINSTALL",
        "UPGRADE",
        "DOWNGRADE",
        "REMOVE"
    ];

    for (var i = 0; i != 5; ++i) {
        var list = changes[i];
        var length = list.length;

        if (length != 0) {
            $("#modifications").append("<div class=\"clearfix\"><div>" +
                "<label>" + cydia.localize($.xml(keys[i])) + "</label>" +
                "<label id=\"c" + i + "\"></label>" +
            "</div></div>");

            var value = "";
            for (var j = 0; j != length; ++j) {
                if (j != 0)
                    value += "<br/>";
                value += $.xml(list[j]);
            }

            $("#c" + i).html(value);
        }
    }
});
