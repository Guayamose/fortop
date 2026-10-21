class CreateBrandImports < ActiveRecord::Migration[8.1]
  def change
    create_table :brand_imports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.text :input_fields
      t.text :result
      t.string :model
      t.decimal :spent_usd, precision: 12, scale: 6, null: false, default: 0
      t.integer :request_count, null: false, default: 0
      t.jsonb :usage, null: false, default: {}
      t.text :error_message
      t.boolean :retryable, null: false, default: false
      t.timestamps
    end

    create_table :brand_documents do |t|
      t.references :brand_import, null: false, foreign_key: true
      t.text :extracted_text
      t.timestamps
    end

    create_join_table :brands, :brand_documents, table_name: :brand_document_links do |t|
      t.index [ :brand_id, :brand_document_id ], unique: true
      t.index :brand_document_id
    end
    add_foreign_key :brand_document_links, :brands
    add_foreign_key :brand_document_links, :brand_documents

    create_join_table :brand_briefs, :brand_documents, table_name: :brand_brief_documents do |t|
      t.index [ :brand_brief_id, :brand_document_id ], unique: true
      t.index :brand_document_id
    end
    add_foreign_key :brand_brief_documents, :brand_briefs
    add_foreign_key :brand_brief_documents, :brand_documents
  end
end
