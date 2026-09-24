
# ==========================================================#
# ---- Load/install required r packages----------------------------
# ==========================================================#

# List of required packages
packages <- c("rstudioapi", "shiny", "tidyverse", "sf", "leaflet", "plotly", "reactable")

# Identify and install any missing packages
missing_packages <- packages[!(packages %in% installed.packages()[, "Package"])]
if (length(missing_packages) > 0) {
  install.packages(missing_packages)
}

# Load all packages into the environment
invisible(lapply(packages, library, character.only = TRUE))

#=====================================================================
#--Set the working directory ----------------------------------------
#=====================================================================
# Set working directory to ShinyAppDemo folder below

setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

# ====================== #
# ---- Load Data ----
# ====================== #

county_data_sf <- 
  sf::st_read("data/oh_county_data.geojson")

vax_provider_tbl <- 
  readr::read_csv("data/vax_providers.csv") %>% 
  select(-c(latitude, longitude, Prescreening_Website)) %>% 
  rename(`Provider Name` = Place_Name,
         `Vaccine Type` = Vaccine_Type) %>% 
  select(`Provider Name`, `Vaccine Type`, Address, City, Zip, Phone, Website, County)

vax_rate_tbl <-
  readr::read_csv("data/vax_rate_over_time.csv") %>% 
  mutate(`Urban rural status` = factor(`Urban rural status`, levels = c("Large central metro", "Large fringe metro", "Medium metro", "Small metro" , "Micropolitan" , "Non-core"  )))

# ==================================== #
# -------- Generate leaflet map--------
# ==================================== #
pal_vax<-
  leaflet::colorNumeric(
    palette = "YlGn",
    domain = county_data_sf$vaccination_rate
  )

pal_svi<-
  leaflet::colorNumeric(
    palette = "YlOrRd",
    domain = county_data_sf$svi
  )

# Red = most urban, green = most rural. Shared by the map and the bar chart.
urban_colors <- c(
  "Large central metro" = "#d73027",
  "Large fringe metro"  = "#fc8d59",
  "Medium metro"        = "#fee08b",
  "Small metro"         = "#d9ef8b",
  "Micropolitan"        = "#91cf60",
  "Non-core"            = "#1a9850"
)

pal_urban_status <- 
  leaflet::colorFactor(
    palette = unname(urban_colors),
    domain = names(urban_colors),
    ordered = TRUE
  )


leaflet_map <- leaflet::leaflet(
  data = county_data_sf
) %>%
  # The map box stays tall to match the chart and table.
  # Its center is the middle of that tall box, below the first screen,
  # so point it south of Ohio. The state then sits in the visible top.
  leaflet::setView(lng = -82.7, lat = 39.2, zoom = 7) %>%
  leaflet::addTiles() %>%
  
  # > Vaccination Rate ----
leaflet::addPolygons(
  group = "Vaccination Rate",
  stroke = TRUE,
  color = ~pal_vax(vaccination_rate),
  weight = 1,
  opacity = 0.5,
  dashArray = "3",
  fillOpacity = 0.7,
  
  label = ~ paste0(
    "<b>", county, "</b>", "</br>",
    "<b>Vaccination Rate: </b>", "</br>",
    vaccination_rate, "%", "</br>",
    "<b>Number of People Vaccinated: </b></br>",
    N_vaccinated
  ) %>% lapply(htmltools::HTML)
)  %>%
  # > SVI ----
leaflet::addPolygons(
  #data = county_data_sf,
  group = "SVI",
  stroke = TRUE,
  color = ~pal_svi(svi),
  weight = 1,
  opacity = 0.5,
  dashArray = "3",
  fillOpacity = 0.7,
  
  label = ~ paste0(
    "<b>", county, "</b>", "</br>",
    "<b>Social Vulnerability Index: </b>", "</br>",
    svi, "</br>",
    "<b>Category: </b></br>",
    svi_category
  ) %>% lapply(htmltools::HTML)
)  %>%
  
  
  # > Urban Rural Status
  leaflet::addPolygons(
    #data = county_data_sf,
    group = "Urban Rural Status",
    stroke = TRUE,
    color = ~pal_urban_status(urban_rural_status),
    weight = 1,
    opacity = 0.5,
    dashArray = "3",
    fillOpacity = 0.7,
    
    label = ~ paste0(
      "<b>", county, "</b>", "</br>",
      "<b>Urban Rural Status: </b>", "</br>",
      urban_rural_status, "</br>"
    ) %>% lapply(htmltools::HTML)
  )  %>%
  
  # > Legends -----

leaflet::addLegend(
  "topleft",
  pal = pal_vax,
  values = ~vaccination_rate,
  title = "Vaccination Rate",
  opacity = 1,
  layerId = "legend"
) %>%
  
  
  # > Layers Control -----
leaflet::addLayersControl(
  baseGroups = c(
    "Vaccination Rate",
    "SVI",
    "Urban Rural Status"
  ),
  position = "topright",
  options = layersControlOptions(collapsed = FALSE)
) 

# =========================================================================================== #
# -------- Generate bar chart (vaccination uptake time series by urban rural status)--------
# =========================================================================================== #


vax_plot <- 
  ggplot2::ggplot(
    data = vax_rate_tbl, 
    ggplot2::aes(
      x=date,y=`Vaccination rate`,
      fill=`Urban rural status`,
      text = paste("Urban/Rural status : ", `Urban rural status`, "\nDate: ", format(date, "%d %b, %Y"))
    )
  ) +
  
  ggplot2::scale_x_date(date_labels = "%b-%y", date_breaks = "month") +
  ggplot2::geom_col(position="stack")+
  ggplot2::scale_fill_manual(values = urban_colors) +
  ggplot2::theme_bw(base_size = 14)+
  ggplot2::theme(legend.position = "top",
                 legend.text = element_text(size = 8), 
                 legend.title = element_text(size = 10),      
                 axis.title.x = element_text(size = 9),    
                 axis.title.y = element_text(size = 9) ,    
                 axis.text.x = element_text(
                   angle = 0,         
                   hjust = 1,           
                   size = 8            
                 ),
                 axis.text.y = element_blank())+
  ggplot2::ylab("Vaccination rate") +
  ggplot2::coord_cartesian(ylim = c(0, 320)) + ggplot2::xlab("Month-Year")

interactive_plot <- plotly::ggplotly(vax_plot, tooltip=c( "y","text")) %>%
  plotly::layout(
    legend = list(orientation = "h", x = 0, y = 1.15),
    margin = list(t = 30)
  ) %>%
  plotly::config(displayModeBar = FALSE)

# ======================================================= #
# ---- Create reactable object (vax provider table) ----
# ======================================================= #

tbl <- vax_provider_tbl %>%
  reactable::reactable(
    filterable = TRUE, # enable column filtering
    outlined = TRUE,
    highlight = TRUE, # highlights table rows on hover
    # Table Size
    defaultPageSize = 5, minRows = 5
  )


# ================== #
# ---- UI part ----
# ==================#

ui <- function() {
  shiny::fluidPage(shiny::h2(
    "Ohio COVID-19 Vaccination Dashboard",
    align = "center",
    style = "font-weight: bold; margin-bottom: 16px;"
  ),
    shiny::fluidRow(
      shiny::column(
        width = 6,
        shiny::h4(
          "County Map: Vaccination Rate, SVI, and Urban–Rural Status",
          align = "center",
          style = "background-color: #f0f0f0; color: black; font-weight: bold; padding: 8px;"
        ),
        leaflet::leafletOutput(outputId = "map", height = 1060)
      ),
      shiny::column(
        width = 6,
        shiny::h4(
          "Vaccination Rate Over Time by Urban–Rural Status",
          align = "center",
          style = "background-color: #f0f0f0; color: black; font-weight: bold; padding: 8px;"
        ),
        fluidRow(plotly::plotlyOutput(outputId = "vax_plot")),
        shiny::h4(
          "Vaccine Providers",
          align = "center",
          style = "background-color: #f0f0f0; color: black; font-weight: bold; padding: 8px;"
        ),
        fluidRow(reactable::reactableOutput("vax_provider_table"))
        
      )
    )
  )
  
}

# ====================== #
# ---- server part ----
# ======================#

server <- function(input, output, session) {

  
  # =========================== #
  # ---- render: leaflet map ----
  # =========================== #
  
  output$map <- leaflet::renderLeaflet({
    
    leaflet_map
    
  })

  # Show the legend for the selected radio button only.
  shiny::observeEvent(input$map_groups, {
    selected <- input$map_groups
    proxy <- leaflet::leafletProxy("map") %>%
      leaflet::removeControl(layerId = "legend")

    if (selected == "Vaccination Rate") {
      proxy %>% leaflet::addLegend(
        "topleft", pal = pal_vax,
        values = county_data_sf$vaccination_rate,
        title = "Vaccination Rate", opacity = 1, layerId = "legend"
      )
    } else if (selected == "SVI") {
      proxy %>% leaflet::addLegend(
        "topleft", pal = pal_svi,
        values = county_data_sf$svi,
        title = "SVI", opacity = 1, layerId = "legend"
      )
    } else if (selected == "Urban Rural Status") {
      proxy %>% leaflet::addLegend(
        "topleft", pal = pal_urban_status,
        values = county_data_sf$urban_rural_status,
        title = "Urban Rural Status", opacity = 1, layerId = "legend"
      )
    }
  }, ignoreInit = TRUE)

  # =========================== #
  # ---- render: vax plot ----
  # =========================== #
  output$vax_plot <- plotly::renderPlotly({
    
    interactive_plot
    
  })
  
  # ========================================== #
  # ---- render: vaccine provider table ----
  # ========================================== #

  output$vax_provider_table <- reactable::renderReactable({
    
    tbl
  })
}

shiny::shinyApp(ui, server)