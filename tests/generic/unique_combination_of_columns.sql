{#-
  Custom generic test: the combination of the given columns must be unique.
  This is how we assert the GRAIN of a model.
  (Equivalent to dbt_utils.unique_combination_of_columns, written by hand so
  the project has zero package dependencies.)
-#}
{% test unique_combination_of_columns(model, combination_of_columns) %}

select
    {{ combination_of_columns | join(', ') }},
    count(*) as n_rows
from {{ model }}
group by {{ combination_of_columns | join(', ') }}
having count(*) > 1

{% endtest %}
