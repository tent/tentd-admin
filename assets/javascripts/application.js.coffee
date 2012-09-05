#= require jquery
#= require bootstrap

jQuery ->
  ($ '[confirm]').each (index, el) ->
    ($ el).click (e) =>
      unless confirm(($ el).attr('confirm'))
        e.preventDefault()
        return false
