# Money metadata for the demo.
#
# A contract (Job) stores its own explicit ISO 4217 `currency`, exactly like it
# stores its own `base_salary_cents`. Nothing here is used by the calculator:
# amounts are raw integer minor units and the currency code only matters for
# formatting/display. `BY_COUNTRY` just maps the seeded jurisdictions to their
# local currency so demo data and the migration backfill agree on one source.
module Currency
  BY_COUNTRY = {
    "AR" => "ARS",
    "UY" => "UYU"
  }.freeze

  def self.for_country(country)
    BY_COUNTRY[country.to_s.upcase]
  end
end
