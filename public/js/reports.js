function fetch_corpus_report(corpus_name) {
  // delete any traces of previous reports
  $("#corpus-report").html('');
  if (!corpus_name) { // No name, no functionality
    clearInterval(countdown); $("#countdown").html(''); return;}
  $('body').css('cursor', 'progress');
  $.ajax({
    url: "/ajax",
    type: "POST",
    dataType: "json",
    data : {"action":"corpus-report","component":component,"corpus-name":corpus_name},
    cache: false,
    success: function(response) {
      $('body').css('cursor', 'auto');
      $("#corpus-report").html(response.report);
      if (response.alive) {
       $("body").removeClass("no-background");
       $("body").addClass("cogs-background");
      } else {
       $("body").removeClass("cogs-background");
       $("body").addClass("no-background");
      }
      clearInterval(countdown);
      //clearTimeout(alarm_t);
      //alarm_t = setTimeout(function() { fetch_corpus_report(corpus_name); }, interval);
      var seconds_left = interval / 1000;
      countdown = setInterval(function() {
          $('#countdown').html('<p>Auto-refresh in '+(--seconds_left)+' seconds.</p>');
          if (seconds_left <= 0)
          {
              $('#countdown').html('<p>Refreshing...</p>');
              clearInterval(countdown);
              fetch_corpus_report(corpus_name);
          }
      }, 1000);
    }
  });
}
