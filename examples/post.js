function GetCellValues(dataTable) 
{
    var table = document.getElementById(dataTable);
    var i = 0; var Obj = [];
    for (var r = 0; r < table.rows.length; r++) {
        if (table.rows[r].id == 'cite') {
          Obj[i] = [];
          var row = table.rows[r].cells;
          for (var c = 0; c < row.length; c++){        
            var check = row[c].getElementsByTagName('Input');
            if (check.length>0){
              if (check[0].checked) {Obj[i][c]=1;} else {Obj[i][c]=0;}
            } else {
              Obj[i][c] =row[c].innerHTML;
            }
          }
          i = i+1;
        }
    }
    var jsonString = JSON.stringify(Obj);
    document.getElementById('out').innerHTML = jsonString;
    //var XMLHttpRequestObj = FileResort.Utils.createRequest();
    //XMLHttpRequestObj.open("POST", "/handle_table.pl", true);
    //XMLHttpRequestObj.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    //XMLHttpRequestObj.send(requestData);
}

function initAuth() {
  // attach popups to every author list cell
  var rows = document.getElementsByTagName("tr");
  for (var i = 0; i<rows.length; i++) {
    if (rows[i].id == "cite") {
      var col = rows[i].cells[5];
      col.contentEditable=false;
      col.addEventListener("click",HandleAuth,false);
    }
  }
}

function ShowAuth(el) {

  // get author list
  var s = el.textContent;
  var bits = s.split(/ and /);
  var str = '';
  for (var i = 0; i<bits.length; i++) {
     str += bits[i]+"\n";
  }

  // create popup
  var m = document.createElement("div");
  m.id = "auth";
  m.style.cssText="position:absolute; background:#0E73B9; padding:10px; box-shadow:10px 10px 5px #888888; border:1px solid;";
  // textarea with authors, one per line
  m.innerHTML = '<textarea rows="'+(bits.length+2)+'">'+str+'</textarea><br>';
  // save button
  var save = document.createElement("input");
  save.type="button"; save.value="Save"; save.addEventListener("click", HandleAuth, false);
  // cancel button
  var cancel = document.createElement("input");
  cancel.type="button"; cancel.value="Cancel"; cancel.addEventListener("click", HandleAuth, false);
  m.appendChild(save);m.appendChild(cancel);

  // insert it into cell
  el.insertBefore(m,el.firstChild);

  // display it
  m.style.display="block";
}

function CloseAuth(el) {
  var m = el.parentNode;
  var td = m.parentNode;
  if (td == null) return; // to handle multiple clicks due to bubbling
  if (el.value == "Save") {
    // extract author list info
    var auths = m.firstChild.value;
    auths = auths.replace(/\n/g,' and ');
    auths = auths.replace(/^ and /,'');
    auths = auths.replace(/ and $/,'');
    // delete popup
    td.removeChild(td.firstChild);
    // update table entry
    td.textContent=auths;
  } else {
    // just delete popup
    td.removeChild(td.firstChild);
  }
}

function HandleAuth() {
  var el = event.target || event.srcElement;
  if (el.tagName == "INPUT") {
    // save or cancel button
    CloseAuth(el);
  } else if (el.tagName == "TD") {
    ShowAuth(el);
  }
}

// add click event listeners ...
window.addEventListener("load", initAuth, false);
