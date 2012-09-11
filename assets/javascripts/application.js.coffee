#= require jquery
#= require bootstrap
#= require chosen.jquery

newIndexTime = (input_node) ->
  new_index = $(input_node).attr('name').match(/(new_\d+)/)?[1]
  return 0 unless new_index
  new_index_time = parseInt(new_index.match(/(\d+)/)?[1])
  new_index_time || 0

jQuery ->
  ($ '[confirm]').each (index, el) ->
    ($ el).click (e) =>
      unless confirm(($ el).attr('confirm'))
        e.preventDefault()
        return false

  ($ 'select').chosen
    create_option: (name) ->
      chosen = @
      chosen.append_option { text: name, value: name }
      $(chosen.search_field).val("")
      chosen.search_field_scale()
      false
