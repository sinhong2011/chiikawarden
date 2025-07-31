use sqlx::sqlite::SqlitePool;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Test the exact connection string format we're using
    let connection_string = "sqlite://test.db?mode=rwc";
    
    println!("Testing connection string: {}", connection_string);
    
    // Try to create a connection pool
    let pool = sqlx::sqlite::SqlitePoolOptions::new()
        .max_connections(50)
        .min_connections(5)
        .acquire_timeout(std::time::Duration::from_secs(30))
        .idle_timeout(std::time::Duration::from_secs(600))
        .max_lifetime(std::time::Duration::from_secs(1800))
        .connect_lazy(&connection_string);
    
    println!("Connection pool created successfully");
    
    // Test a simple query
    let result = sqlx::query_scalar::<_, i32>("SELECT 1")
        .fetch_one(&pool)
        .await?;
    
    println!("Query result: {}", result);
    
    // Clean up
    std::fs::remove_file("test.db").ok();
    
    println!("Test completed successfully!");
    Ok(())
}
