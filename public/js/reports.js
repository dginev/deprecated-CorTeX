function fetch_report(type,name) {
  // delete any traces of previous reports
  var report_type = type+"-report";
  $("#"+report_type).html('');
  if (!name) { // No name, no functionality
    clearInterval(countdown); $("#countdown").html(''); return;}
  $('body').css('cursor', 'progress');
  $.ajax({
    url: "/ajax",
    type: "POST",
    dataType: "json",
    data : {"action":report_type,"component":component,"name":name},
    cache: false,
    success: function(response) {
      $('body').css('cursor', 'auto');
      $("#"+report_type).html(response.report);
      if (response.alive) {
       $("body").removeClass("no-background");
       $("body").addClass("cogs-background");
      } else {
       $("body").removeClass("cogs-background");
       $("body").addClass("no-background");
      }
      clearInterval(countdown);
      //clearTimeout(alarm_t);
      //alarm_t = setTimeout(function() { fetch_corpus_report(name); }, interval);
      var seconds_left = interval / 1000;
      countdown = setInterval(function() {
          $('#countdown').html('<p>Auto-refresh in '+(--seconds_left)+' seconds.</p>');
          if (seconds_left <= 0)
          {
              $('#countdown').html('<p>Refreshing...</p>');
              clearInterval(countdown);
              fetch_report("corpus",name);
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