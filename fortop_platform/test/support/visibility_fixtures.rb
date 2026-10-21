module VisibilityFixtures
  def visibility_brand(user: nil)
    user ||= User.create!(github_id: SecureRandom.random_number(1_000_000_000), login: "visibility-builder", github_token: "fake-token")
    user.brands.create!(name: "Nébula", website: "https://nebula.com", brief: "Ofrecemos software de facturación para pequeños negocios de España. Nuestro valor es la sencillez y el soporte cercano.", markets: [ { "name" => "España", "language" => "es" } ])
  end

  def visibility_study(brand: visibility_brand, **options)
    Visibility::Studies.create!(brand, question_count: 6, repetitions: 2, **options)
  end

  def complete_visibility(study, client: FakeVisibilityClient.new)
    160.times do
      break unless study.reload.work_pending?
      Visibility::Pipeline.new(study, client: client, resolver: ->(url) { url }).step
    end
    assert study.reload.completed?, study.error_message
    study
  end

  class FakeVisibilityClient
    attr_reader :requests
    attr_accessor :failure, :invalid_panel, :uncertain

    ANSWER = "Recomiendo Nébula para pequeños negocios: Nébula ofrece facturación sencilla. Otra opción es Contalia."

    def initialize
      @requests = []
    end

    def generate(**request)
      requests << request
      raise failure if failure
      schema, prompt = request.values_at(:schema, :prompt)
      props = schema&.fetch(:properties, {}) || {}
      data = if props.key?("fields")
        { "fields" => { "name" => "Nébula", "website" => "https://nebula.com", "aliases_text" => "Nebula", "brief" => "Software de facturación sencillo para pequeños negocios de España, con soporte cercano y gestión de presupuestos.", "markets_text" => "España | es", "known_competitors" => "Contalia" }, "warnings" => [] }
      elsif props.key?("business")
        { "business" => "Software de facturación", "value_proposition" => "Sencillez y cercanía", "audiences" => [ "Pequeños negocios" ], "products" => [ "Facturación" ], "needs" => [ "Emitir facturas" ], "assumptions" => [ "Validar el sector prioritario" ], "summary" => "Una herramienta para pymes." }
      elsif props.key?("competitors")
        { "competitors" => [ { "name" => "Contalia", "website" => "https://contalia.com", "aliases" => [], "kind" => "direct", "reason" => "Ayuda a pymes a facturar en el mismo mercado.", "markets" => [ "España" ], "source_indexes" => [ 0 ] } ], "facts" => [ { "claim" => "Nébula ofrece facturación.", "source_indexes" => [ 0 ] } ], "market_summary" => "Mercado de facturación." }
      elsif props.key?("questions")
        { "questions" => 6.times.map { |index| { "text" => invalid_panel ? "¿Qué ofrece Nébula para mi empresa #{index}?" : (index == 5 ? "¿Qué ofrece Nébula para una pequeña empresa?" : "¿Qué software de facturación conviene para el caso de negocio #{index}?"), "intent" => %w[discovery consideration decision][index % 3], "topic" => "Facturación", "audience" => "Pequeñas empresas", "branded" => index == 5 } } }
      elsif props.key?("mentions")
        { "mentions" => [ { "entity_key" => "brand", "quote" => "Nébula ofrece facturación sencilla.", "recommendation_quote" => "Recomiendo Nébula para pequeños negocios", "sentiment" => "positive", "certainty" => uncertain ? "uncertain" : "confirmed", "attributes" => [ { "label" => "Sencillez", "quote" => "Nébula ofrece facturación sencilla." } ] } ], "claims_to_review" => [] }
      elsif props.key?("insights")
        ids = prompt.scan(/"id":(\d+)/).flatten.map(&:to_i).first(2)
        { "summary" => "La marca aparece en la muestra analizada. Conviene ampliar el panel antes de generalizar.", "insights" => [ { "title" => "Sencillez reconocida", "description" => "Las respuestas describen una herramienta sencilla.", "observation_ids" => ids } ], "actions" => [ { "title" => "Comprobar datos estructurados de producto", "description" => "Validar en el código si la oferta está descrita con datos estructurados correctos.", "kind" => "technical", "priority" => "high", "effort" => "low", "observation_ids" => ids } ] }
      end
      grounded = request.fetch(:grounded)
      text = data ? JSON.generate(data) : (prompt.start_with?("Search the public web") ? "Nébula ofrece facturación. Contalia es una alternativa para pymes. Fuente oficial consultada." : ANSWER)
      source = { "url" => "https://nebula.com/producto", "title" => "Nébula · producto", "excerpts" => [ "Nébula ofrece facturación sencilla." ], "cited" => true }
      Visibility::GoogleClient::Result.new(text: text, citations: grounded ? [ source ] : [], search_queries: grounded ? [ "software facturación" ] : [], search_entry_point: grounded ? '<div><a href="https://www.google.com/search?q=facturacion">Google Search</a></div>' : nil, usage: { "input_tokens" => 100, "output_tokens" => 200, "total_tokens" => 300, "search_queries" => grounded ? 1 : 0 }, model_version: "gemini-fixture-v1")
    end
  end
end
