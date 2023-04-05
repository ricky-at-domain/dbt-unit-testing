{% macro mock_ref(model_name, options={}) %}
  {% set mock = {
     "type": 'mock',
     "resource_type": 'model',
     "name": model_name,
     "options": options,
     "input_values": caller(),
    }
  %} 
  {{ return (dbt_unit_testing.append_json(mock)) }}
{% endmacro %}

{% macro mock_source(source_name, table_name, options={}) %}
  {% if not table_name %}
    {{ dbt_unit_testing.raise_error('Table name must be provided for source') }}
  {% endif %}
  {% set mock = {
     "type": 'mock',
     "resource_type": 'source',
     "name": table_name,
     "source_name": source_name,
     "options": options,
     "input_values": caller(),
    }
  %} 
  {{ return (dbt_unit_testing.append_json(mock)) }}
{% endmacro %}

{% macro expect(options={}) %}
  {% set expectations = {
      "type": "expectations",
      "options": options,
      "input_values": caller(),
    }
  %} 
  {{ return (dbt_unit_testing.append_json(expectations)) }}
{% endmacro %}

{% macro append_json(json) %}
  {{ return (json | tojson() ~ '####_JSON_LINE_DELIMITER_####') }}
{% endmacro %}

{% macro split_json_str(json_str) %}
  {% set lines = json_str.split('####_JSON_LINE_DELIMITER_####') | map('trim') | reject('==', '') | list %}
  {{ return (dbt_unit_testing.map(lines, fromjson)) }}
{% endmacro %}

{% macro enrich_mock_sql_with_missing_columns(mock, options) %}
  {% set model_node = dbt_unit_testing.node_by_id(mock.unique_id) %}
  {% set model_name = model_node.name %}
  {% set input_values_sql = mock.input_values %}

  {% set model_columns = dbt_unit_testing.get_from_cache("COLUMNS", model_node.name) %}
  {% if not model_columns %}
    {% set model_sql = dbt_unit_testing.build_node_sql(model_node, complete=true, use_database_models=options.use_database_models) %}
    {% set model_columns = dbt_unit_testing.extract_columns_list(model_sql) %}
    {{ dbt_unit_testing.cache("COLUMNS", model_node.name, model_columns)}}
  {% else %}
    {{ dbt_unit_testing.verbose("CACHE HIT for " ~ model_node.name ~ " COLUMNS") }}
  {% endif %}
  
  {% set input_columns = dbt_unit_testing.extract_columns_list(input_values_sql) %}
  {% set missing_columns = dbt_unit_testing.extract_columns_difference(model_columns, input_columns) %}

  {%- if missing_columns -%}
    {% set input_values_sql %}
      {% set node_sql = dbt_unit_testing.build_node_sql(model_node, use_database_models=options.use_database_models) %}
        select * from ({{ input_values_sql }}) as m1
        left join (select {{ missing_columns | join (",")}}
                  from ({{ node_sql }}) as m2) as m3 on false
    {%- endset -%}
  {%- endif -%}
  {% do mock.update({"input_values": input_values_sql}) %}
{% endmacro %}

{%- macro mock_template(model_name, project='') -%}
  {%- set unique_id = "model." ~project~ "." ~model_name -%}
  {%- set src_models = [] -%}
  {%- set ref_models = [] -%}
  {%- set depends_on = [] -%}
  {%- for model in graph.nodes.values() | selectattr("resource_type", "equalto", "model") | selectattr("unique_id", "equalto", unique_id) -%}
    {%- for ref_model in model.refs if ref_model not in  ref_models -%}
      {{ ref_models.append(ref_model) or "" }}
    {%- endfor -%}
    {%- for src_model in model.sources if src_model not in  src_models -%}
      {{ src_models.append(src_model) or "" }}
    {%- endfor -%}
    {%- for ref_model in ref_models  -%}
      {{ depends_on.append("-- depends_on: {{ ref('" ~ ref_model[0] ~ "') }}") or "" }}
    {%- endfor -%}
    {{ depends_on.append("") or "" }}
    {{ depends_on.append("") or "" }}
    {{ depends_on.append("{% call dbt_unit_testing.test('" ~model_name~ "', '<PUT DESCRIPTION HERE>') %}") or "" }}
    {{ depends_on.append("") or "" }}
    {%- for ref_model in ref_models -%}
      {{ depends_on.append("  {% call dbt_unit_testing.mock_ref('" ~ref_model[0]~ "') %}") or "" }}
        {{ depends_on.append("    -- PUT YOUR MOCK DATA HERE") or "" }}
      {{ depends_on.append("  {% endcall %}") or "" }}
      {{ depends_on.append("") or "" }}
    {%- endfor -%}
    {%- for src_model in src_models -%}
      {{ depends_on.append("  {% call dbt_unit_testing.mock_source('" ~src_model[0]~"','"~ src_model[1] ~ "') %}") or "" }}
        {{ depends_on.append("    -- PUT YOUR MOCK DATA HERE") or "" }}
      {{ depends_on.append("  {% endcall %}") or "" }}
      {{ depends_on.append("") or "" }}
    {%- endfor -%}
    {{ depends_on.append("  {% call dbt_unit_testing.expect() %}") or "" }}
      {{ depends_on.append("    -- PUT YOUR MOCK EXPECTATION DATA HERE") or "" }}
    {{ depends_on.append("  {% endcall %}") or "" }}
    {{ depends_on.append("") or "" }}
    {{ depends_on.append("{% endcall %}") or "" }}
  {%- endfor -%}
  {{ depends_on | join("\n") }}
  {%- for statement in depends_on -%}
    {{ print(statement) }}
  {%- endfor -%}
{%- endmacro -%}
