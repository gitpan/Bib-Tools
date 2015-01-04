function GetCellValues(dataTable) 
{
    var Obj = [];
    var table = document.getElementById(dataTable);
    for (var r = 0, r < table.rows.length; r++) {
        Obj[r] = [];
        for (var c = 0, c < table.rows[r].cells.length; c++){        
            Obj[r][c] =table.rows[r].cells[c].innerHTML;
        }
    }
    var jsonString = encodeURIComponent(JSON.stringify(Obj));
    alert("Save your data "+ jsonString);
    //var XMLHttpRequestObj = FileResort.Utils.createRequest();
    //XMLHttpRequestObj.open("POST", "/handle_table.pl", true);
    //XMLHttpRequestObj.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    //XMLHttpRequestObj.send(requestData);
}
