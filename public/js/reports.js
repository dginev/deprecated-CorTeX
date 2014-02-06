var countdown;
var interval = 60000;   //number of mili seconds between each call
function fetch_report(type,name) {
  // delete any traces of previous reports
  var report_type = type+"-report";
  if (!name) { // No name, no functionality
    $("#"+report_type).html('');
    clearInterval(countdown); $("#countdown").html(''); return;}
  $('body').css('cursor', 'progress');
  $.ajax({
    url: "/ajax",
    type: "POST",
    dataType: "json",
    data : {"action":report_type,"name":name},
    cache: false,
    success: function(response) {
      $('body').css('cursor', 'auto');
      $("#message").html("<p><br><b>"+response.message+"</b><br></p>");
      $("#"+report_type).html(response.report);
      clearInterval(countdown);
      var seconds_left = interval / 1000;
      countdown = setInterval(function() {
          $('#countdown').html('<p>Auto-refresh in '+(--seconds_left)+' seconds.</p>');
          if (seconds_left <= 0)
          {
              $('#countdown').html('<p>Refreshing...</p>');
              clearInterval(countdown);
              fetch_report(type,name);
              if (type == "corpus") {fetch_pending_corpora_report();}
          }
      }, 1000);
    }
  });
}

function fetch_corpus_report(corpus_name) {
  return fetch_report("corpus",corpus_name);
}
function fetch_service_report(service_name) {
  return fetch_report("service",service_name);
}

function fetch_classic_report(corpus_name,service_name,component,countby) {
  $('body').css('cursor', 'progress');
  $.ajax({
      url: "/ajax",
      type: "POST",
      dataType: "json",
      data : {"action":"classic-report","component":component,"corpus":corpus_name,
              "service":service_name,"countby":countby},
      cache: false,
      success: function(response) {
          $('body').css('cursor', 'auto');
          $("#report").html(response.report);
          if (response.alive > 0) {
           $("body").removeClass("no-background");
           $("body").addClass("cogs-background");
          } else {
           $("body").removeClass("cogs-background");
           $("body").addClass("no-background");
          }
       
          $('select.selectcountby').change(function() {
            var thiscountby="";
            $("select.selectcountby option:selected").each(function () {
              thiscountby += $(this).val();
            });
            fetch_classic_report(corpus_name,service_name,component,thiscountby);
          });

          clearInterval(countdown);
          //clearTimeout(alarm_t);
          //alarm_t = setTimeout(function() { refresh(); }, interval);
          var seconds_left = interval / 1000;
          countdown = setInterval(function() {
              $('#countdown').html('<p>Auto-refresh in '+(--seconds_left)+' seconds.</p>');
              if (seconds_left <= 0)
              {
                  $('#countdown').html('<p>Refreshing...</p>');
                  clearInterval(countdown);
                  fetch_classic_report(corpus_name,service_name,component,countby);
              }
          }, 1000);
          $('tr.stats-row').find('td:first').addClass('zoom-td').prepend(
            "<button class='zoom-button'>Expand</button>");
          $(".zoom-button").button({
              icons: {
                  primary: 'ui-icon-circle-plus'
              }, text: false
              }).css({
                  'cursor': 'pointer',
                  'float' : 'left',
                  'width': '25px'
          });
          $("span.ok").parent().children(".zoom-button").button({
              icons: {
                  primary: 'ui-icon-circle-zoomin'
              }, text: false
              }).css({
                  'cursor': 'pointer',
                  'float' : 'left',
                  'width': '25px'
          });
          $("span.what").parent().children(".zoom-button").button({
              icons: {
                  primary: 'ui-icon-circle-zoomin'
              }, text: false
              }).css({
                  'cursor': 'pointer',
                  'float' : 'left',
                  'width': '25px'
          });
          var parts = component.split(":");
          var thisclass = parts.pop();
          var thisparts = thisclass.split(' ');
          var thislevel = thisparts[1];
          if (thislevel == 'category') {
              $("span.what").parentsUntil('table').parent().parent().parent().prev().find(".zoom-button").button({
              icons: {
                  primary: 'ui-icon-circle-minus'
              }, text: false
              }).css({
                  'cursor': 'pointer',
                  'float' : 'left',
                  'width': '25px'
              });                    
          }
          if ((thislevel == 'severity') || (thislevel == 'category')) {
              $("span.category").parentsUntil('table').parent().parent().parent().prev().find(".zoom-button").button({
                  icons: {
                      primary: 'ui-icon-circle-minus'
                  }, text: false
                  }).css({
                      'cursor': 'pointer',
                      'float' : 'left',
                      'width': '25px'
                  });
          }
              //if (component.indexOf(thisclass) != -1) {
                //      $('.zoom-button').text('Collapse');
                  //    zoom_icon = "ui-icon-circle-minus";
              //}
          $('.zoom-button').click(function () {
              var description='';
              var thisclass = ($(this).parent().parent().find('td > span').attr('class'));
              var thisparts = thisclass.split(' ');
              var thislevel = thisparts[1];
              if ((thisclass != 'ok severity') && (component.indexOf(thisclass) != -1)) {
                  while (component.indexOf(thisclass) != -1) {
                      var parts = component.split(":");
                      parts.pop();
                      component = parts.join(":");
                  }
              } else {
                  while (component.indexOf(thislevel) != -1) {
                      var parts = component.split(":");
                      parts.pop();
                      component = parts.join(":");
                  }
                  component = component+':'+thisclass;
              }
              var level = component.split(":").length - 1;
              if ((level >= 3) || thisclass == 'ok severity') {
                  window.location.href = "/retval_detail?"+
                  $.param({
                    "corpus":corpus_name,
                    "service":service_name,
                    "component":component,
                    "countby":countby
                  });
              }
              fetch_classic_report(corpus_name,service_name,component,countby);
          });
          $('tr.stats-row').hover(function() {
              $(this).find('td').last().append("<button class='rerun-button'>Rerun</button>");
              var thisclass = $(this).find('td > span').attr('class');
              var thisparts = thisclass.split(' ');
              var thislevel = thisparts[1];
              $(".rerun-button").button({
              icons: {
                  primary: "ui-icon-refresh"
              }, text: false
              }).css({
                  'cursor': 'pointer',
                  'float' : 'right',                        
                  'width': '25px'
              });
              $('.rerun-button').click(function() {
                  var description='';
                  var thisclass = ($(this).parent().parent().find('td > span').attr('class'));
                  var thisparts = thisclass.split(' ');
                  var thislevel = thisparts[1];
                  coded_description = component;
                  if (coded_description.indexOf(thislevel) != -1) {
                      while (coded_description.indexOf(thislevel) != -1) {
                          var parts = coded_description.split(":");
                          parts.pop();
                          coded_description = parts.join(":");
                      }
                  }
                  coded_description = coded_description + ':' + thisclass;
                  var parts = coded_description.split(':');
                  for (var part in parts) {
                      var pair = parts[part].split(' ');
                      if (pair.length>1) {
                          description = description+"\n"+pair[1]+": "+pair[0]+"\n";
                      }
                  }
                  var confirmed = confirm("Mark for Rerun\n"+description);
                  if (confirmed) {
                      $.ajax({
                          url: "/ajax",
                          type: "POST",
                          dataType: "json",
                          data : {"action":"queue-rerun",
                                  "component":coded_description,
                                  "corpus":corpus_name,
                                  "service":service_name},
                          cache: false,
                          success: function(response) { 
                                  alert (response.message);
                                  var parts = coded_description.split(":");
                                  parts.pop();
                                  coded_description = parts.join(":");
                                  fetch_classic_report(corpus_name,service_name,coded_description,countby); }
                      });
                  }
              });
          },
          function(){
            //  $('.zoom-button').remove();
              $('.rerun-button').remove();
          });
      }
  });
}

function getURLParameter(name) {
    return decodeURI(
        (RegExp(name + '=' + '(.+?)(&|$)').exec(location.search)||[,null])[1]
    ).replace(/\+/g,' ').replace(/%3A/g,':');
}

function fetch_description(type,name) {
  // delete any traces of previous reports
  var description_type = type+"-description";
  if ((!name) || name == "Analyzers" || name == "Converters" || name == "Aggregators")
  { // No name, no functionality
    $("#update-description").css('display', 'none');
   return;}
  $('body').css('cursor', 'progress');
  $.ajax({
    url: "/ajax",
    type: "POST",
    dataType: "json",
    data : {"action":description_type,"name":name},
    cache: false,
    success: function(response) {
      $('body').css('cursor', 'auto');
      if (response.message) {
        $("#message").html("<p><br><b>"+response.message+"</b><br></p>"); }
      var table = $("#update-description");
      $('#update-name').val(response.name);
      $('#update-oldname').val(response.name);
      $('#update-version').val(response.version);
      $('#update-id').val(response.iid);
      $('#update-id-label').text(response.iid);
      $('#update-oldid').val(response.iid);
      $('#update-url').val(response.url);
      $('#update-xpath').val(response.xpath);
      $('#update-inputformat').val(response.inputformat);
      $('#update-outputformat').val(response.outputformat);
      if (response.entrysetup) {
        $('#update-entry-setup').val('complex'); }
      else {
        $('#update-entry-setup').val('simple'); }
      $('#update-resource').val(response.resource);
      $("#update-type option").filter(function() {
        return $(this).val() == response.type; 
      }).prop('selected', true);
      $("#update-type").change();
      $("#update-requires-converter option").filter(function() {
        return $(this).text() == response.inputconverter; 
      }).prop('selected', true);
      $("#update-requires-converter").change();

      // Corpora:
      // First unmark all
      var all_corpora_checks = $('input:checkbox[name="update-corpora\\[\\]"]');
      all_corpora_checks.prop('checked',false);
      var corpora = response.corpora;
      for (index in corpora) {
        var corpus = corpora[index];
        var corpus_check = $('input:checkbox[name="update-corpora\\[\\]"][value='+corpus+']');
        corpus_check.prop('checked', true);
      }
      // TODO: Dependencies
      var checkbox = $('input:checkbox[name="update-requires-analyses\\[\\]"]');
      var label = checkbox.next('span');
      checkbox.show(); label.show();

      checkbox = $('input:checkbox[name="update-requires-analyses\\[\\]"][value="'+name+'"]');
      label = checkbox.next('span');
      checkbox.hide(); label.hide();

      var checkbox = $('input:checkbox[name="update-requires-aggregation\\[\\]"]');
      var label = checkbox.next('span');
      checkbox.show(); label.show();

      checkbox = $('input:checkbox[name="update-requires-aggregation\\[\\]"][value="'+name+'"]');
      label = checkbox.next('span');
      checkbox.hide(); label.hide();

      $("select[name='update-requires-converter'] option").show();
      $("select[name='update-requires-converter'] option[value='" + name + "']").hide();

      table.css('display', '');
      $("#accordion").accordion("refresh");
    }
  });
}

function fetch_corpus_description(corpus_name) {
  return fetch_description("corpus",corpus_name);
}
function fetch_service_description(service_name) {
  return fetch_description("service",service_name);
}

function fetch_pending_corpora_report() {
    $.ajax({
    url: "/ajax",
    type: "POST",
    dataType: "json",
    data : {"action":'pending-corpora-report'},
    cache: false,
    success: function(response) {
      $("#pending-corpora-report").html(response.report); }
  }); 
}