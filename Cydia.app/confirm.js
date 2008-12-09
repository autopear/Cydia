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

        var size = sizes[2];
        var negative;

        if (size.charAt(0) != '-')
            negative = false;
        else {
            negative = true;
            size = size.substr(1);
        }

        $("#disk-key").html(negative ? "Disk Freeing" : "Disk Using");
        $("#disk-value").html($.xml(size));
    } else for (var i = 0; i != issues.length; ++i) {
        document.title = "Cannot Comply";

        $("._issues").remove();

        var issue = issues[i];

        $("#issues").append(
            "<label style=\"color: #704d4d\">" + issue[0] + "</label>" +
            "<fieldset style=\"background-color: #dddddd\" class=\"clearfix\" id=\"i" + i + "\"></fieldset>"
        );

        for (var j = 1; j != issue.length; ++j) {
            var entry = issue[j];
            var type = entry[0];
            if (type == "PreDepends")
                type = "Depends";
            $("#i" + i).append("<div>" +
                "<label>" + type + "</label>" +
                "<div>" + entry[1] + " " + entry[3] + "</div>" +
            "</div>");
        }
    }

    var keys = [
        "Install",
        "Reinstall",
        "Upgrade",
        "Downgrade",
        "Remove"
    ];

    for (var i = 0; i != 5; ++i) {
        var list = changes[i];
        var length = list.length;

        if (length != 0) {
            $("#modifications").append("<div class=\"clearfix\">" +
                "<label>" + keys[i] + "</label>" +
                "<div id=\"c" + i + "\"></div>" +
            "</div>");

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
