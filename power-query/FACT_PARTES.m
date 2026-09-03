// FACT_PARTES  (versión de reparto público: origen local, no SharePoint)
shared FACT_PARTES = let
    // ---- ORIGEN LOCAL (snapshot anonimizado) --------------------------------
    // Sustituye a:  SharePoint.Tables("https://<tenant>.sharepoint.com/sites/partes")
    // Lee la tabla ORIGEN_PARTES incrustada en el propio libro, de modo que
    // cualquiera puede abrir y actualizar el archivo sin acceso al SharePoint.
    Origen = Excel.CurrentWorkbook(){[Name="ORIGEN_PARTES"]}[Content],
    #"Tipo cambiado" = Table.TransformColumnTypes(Origen,{
        {"Id", Int64.Type},
        {"Hora entrada", type datetime}, {"Hora salida", type datetime},
        {"Horasdedesplazamiento(iday", type number}, {"KM(sihayvehículoprop", type number},
        {"Nºpernoctaciones", Int64.Type}
    }),
    #"Columnas con nombre cambiado" = Table.AddColumn(#"Tipo cambiado", "ID.1", each [Id], Int64.Type),
    Personalizado1 = Table.TransformColumns(
        #"Columnas con nombre cambiado",
        {
            {"Hora entrada", each DateTimeZone.RemoveZone(DateTimeZone.ToLocal(DateTime.AddZone(_, 0, 0))), type datetime},
            {"Hora salida",  each DateTimeZone.RemoveZone(DateTimeZone.ToLocal(DateTime.AddZone(_, 0, 0))), type datetime}
        }
    ),
    // Author.FirstName / Author.LastName / Author.GUID y Categoría (= antiguo Author.JobTitle,
    // categoría de nómina traída por Power Automate) ya vienen como columnas en ORIGEN_PARTES.
    #"Columnas con nombre cambiado2" = Personalizado1,
    // ------------------------------------------------------------------------
    #"Personalizada agregada" = Table.AddColumn(#"Columnas con nombre cambiado2", "Trabajador", each [Author.FirstName] & " " &[Author.LastName]),
    #"Personalizada agregada1" = Table.AddColumn(#"Personalizada agregada", "Horas", each Duration.TotalHours([Hora salida]-[Hora entrada])),
    #"Personalizada agregada2" = Table.AddColumn(#"Personalizada agregada1", "FechaBase", each Date.From([Hora entrada])),
    #"Personalizada agregada2b" = Table.AddColumn(#"Personalizada agregada2", "Jornada", each 
    if Time.From([Hora entrada]) < #time(6,0,0) then 
        Date.AddDays(Date.From([Hora entrada]), -1) 
    else 
        Date.From([Hora entrada])
),
    #"Personalizada agregada3" = Table.AddColumn(#"Personalizada agregada2b", "Corte22", each DateTime.From([FechaBase]) + #duration(0,22,0,0)),
    #"Personalizada agregada4" = Table.AddColumn(#"Personalizada agregada3", "Corte06", each DateTime.From([FechaBase]) + #duration(1,6,0,0)),
    #"Personalizada agregada5" = Table.AddColumn(#"Personalizada agregada4", "ListaCortes", each {[Hora entrada], [Corte22], [Corte06], [Hora salida]}),
    #"Personalizada agregada6" = Table.AddColumn(#"Personalizada agregada5", "ListaCortesValidos", each List.Sort(
    List.Select(
        [ListaCortes],
        each _ >= [Inicio] and _ <= [Fin]
    )
)),
    #"Columnas quitadas" = Table.RemoveColumns(#"Personalizada agregada6",{"ListaCortesValidos"}),
    #"Personalizada agregada7" = Table.AddColumn(#"Columnas quitadas", "ListaCortesValidos", each let
    listaBase = {
        try [Hora entrada] otherwise null,
        try [Corte22] otherwise null,
        try [Corte06] otherwise null,
        try [Hora salida] otherwise null
    },

    listaLimpia = List.RemoveNulls(listaBase),

    listaFiltrada = List.Select(
        listaLimpia,
        each _ >= [Hora entrada] and _ <= [Hora salida]
    )
in
    List.Sort(listaFiltrada)),
    #"Personalizada agregada8" = Table.AddColumn(#"Personalizada agregada7", "Tramos", each let
    inicio = [Hora entrada],
    fin = [Hora salida],

    fecha = Date.From(inicio),

    corte22 = DateTime.From(fecha) + #duration(0,22,0,0),
    corte06 = DateTime.From(fecha) + #duration(1,6,0,0),

    lista = List.RemoveNulls({inicio, corte22, corte06, fin}),
    listaOrdenada = List.Sort(lista),

    listaValidos = List.Select(listaOrdenada, each _ >= inicio and _ <= fin)

in
    if List.Count(listaValidos) < 2 then
        {}
    else
        List.Transform(
            {0..(List.Count(listaValidos)-2)},
            (i) => [
                InicioTramo = listaValidos{i},
                FinTramo = listaValidos{i+1}
            ]
        )),
    #"Se expandió Tramos" = Table.ExpandListColumn(#"Personalizada agregada8", "Tramos"),
    #"Se expandió Tramos1" = Table.ExpandRecordColumn(#"Se expandió Tramos", "Tramos", {"InicioTramo", "FinTramo"}, {"Tramos.InicioTramo", "Tramos.FinTramo"}),
    #"Columnas con nombre cambiado1" = Table.RenameColumns(#"Se expandió Tramos1",{{"Tramos.InicioTramo", "InicioTramo"}, {"Tramos.FinTramo", "FinTramo"}}),
    #"Personalizada agregada9" = Table.AddColumn(#"Columnas con nombre cambiado1", "HorasTramo", each Duration.TotalHours([FinTramo] - [InicioTramo])),
    #"Personalizada agregada10" = Table.AddColumn(
    #"Personalizada agregada9",
    "TipoHora",
    each
        let
            FechaTramo = Date.From([InicioTramo]),
            HoraTramo = Time.From([InicioTramo]),
            EsFinSemana = Date.DayOfWeek(FechaTramo, Day.Monday) >= 5,
            EsHorarioNocturno = HoraTramo >= #time(22,0,0) or HoraTramo < #time(6,0,0)
        in
            if EsFinSemana or EsHorarioNocturno then "NOCTURNA" else "ORDINARIA",
    type text
),
    #"Filas ordenadas" = Table.Sort(#"Personalizada agregada10",{{"Author.GUID", Order.Ascending}, {"Jornada", Order.Ascending}, {"InicioTramo", Order.Ascending}}),
    #"Filas agrupadas" = Table.Group(#"Filas ordenadas", {"Author.GUID", "Jornada"}, {{"TablaIndexada", each _, type table}}),
    #"Personalizada agregada11" = Table.AddColumn(#"Filas agrupadas", "TablaIndexada.1", each Table.AddIndexColumn([TablaIndexada], "Orden", 1, 1)),
    #"Personalizada agregada12" = Table.AddColumn(#"Personalizada agregada11", "TablaAcumulada", each let
    t = [TablaIndexada.1]
in
    Table.AddColumn(
        t,
        "HorasAcumuladas",
        each 
            let
                currentOrder = [Orden]
            in
                List.Sum(
                    List.FirstN(
                        t[HorasTramo],
                        currentOrder
                    )
                )
    )),
    #"Se expandió TablaAcumulada1" = Table.ExpandTableColumn(#"Personalizada agregada12", "TablaAcumulada", {
"Id", "Title", "Tipo de parte", "Cliente", "Hora entrada", "Hora salida",
        "Horasdedesplazamiento(iday", "KM(sihayvehículoprop", "OData_¿Haspernoctado?",
        "Nºpernoctaciones", "Descripcióntrabajos", "Nºpresupuesto", "ID.1",
        "Categoría", "Trabajador", "Horas", "FechaBase", "InicioTramo", "FinTramo",
        "HorasTramo", "TipoHora", "Orden", "HorasAcumuladas", "Categoría_Trabajador", "Sección"
    },
    {
        "TablaAcumulada.Id", "TablaAcumulada.Title", "TablaAcumulada.Tipo de parte", "TablaAcumulada.Cliente",
        "TablaAcumulada.Hora entrada", "TablaAcumulada.Hora salida",
        "TablaAcumulada.Horasdedesplazamiento(iday", "TablaAcumulada.KM(sihayvehículoprop",
        "TablaAcumulada.OData_¿Haspernoctado?", "TablaAcumulada.Nºpernoctaciones",
        "TablaAcumulada.Descripcióntrabajos", "TablaAcumulada.Nºpresupuesto",
        "TablaAcumulada.ID.1", "TablaAcumulada.Categoría", "TablaAcumulada.Trabajador",
        "TablaAcumulada.Horas", "TablaAcumulada.FechaBase", "TablaAcumulada.InicioTramo",
        "TablaAcumulada.FinTramo", "TablaAcumulada.HorasTramo", "TablaAcumulada.TipoHora",
        "TablaAcumulada.Orden", "TablaAcumulada.HorasAcumuladas", "TablaAcumulada.Categoría_Trabajador", "TablaAcumulada.Sección"
    }
),
    #"Personalizada agregada13" = Table.AddColumn(#"Se expandió TablaAcumulada1", "HorasAntes", each [TablaAcumulada.HorasAcumuladas] - [TablaAcumulada.HorasTramo]),
    #"Personalizada agregada14" = Table.AddColumn(#"Personalizada agregada13", "HorasNormales", each if [HorasAntes] >= 8 then 0
else if [TablaAcumulada.HorasAcumuladas] <= 8 then [TablaAcumulada.HorasTramo]
else 8 - [HorasAntes]),
    #"Personalizada agregada15" = Table.AddColumn(#"Personalizada agregada14", "HorasExtra", each [TablaAcumulada.HorasTramo] - [HorasNormales]),
    #"Personalizada agregada16" = Table.AddColumn(
    #"Personalizada agregada15",
    "TipoHoraFinal",
    each
        let
            HorasExtraSafe = try Number.From([HorasExtra]) otherwise 0,
            FechaTramo = try Date.From([TablaAcumulada.InicioTramo]) otherwise null,
            HoraTramo = try Time.From([TablaAcumulada.InicioTramo]) otherwise null,
            EsFinSemana = if FechaTramo = null then false else Date.DayOfWeek(FechaTramo, Day.Monday) >= 5,
            EsHorarioNocturno = if HoraTramo = null then false else (HoraTramo >= #time(22,0,0) or HoraTramo < #time(6,0,0)),
            CriteriosBase = (if EsFinSemana then 1 else 0) + (if EsHorarioNocturno then 1 else 0),
            CriteriosConExtra = CriteriosBase + (if HorasExtraSafe > 0 then 1 else 0)
        in
            if HorasExtraSafe > 0 then
                if CriteriosConExtra >= 2 then "EXTRA ESPECIAL" else "EXTRA ORDINARIA"
            else
                if CriteriosBase >= 2 then "EXTRA ESPECIAL"
                else if CriteriosBase = 1 then "NOCTURNA"
                else "ORDINARIA",
    type text
),
    #"Personalizada agregada17" = Table.AddColumn(#"Personalizada agregada16", "Key", each [TablaAcumulada.Categoría_Trabajador] & "|" & [TipoHoraFinal]),
    #"Personalizada agregada18" = Table.AddColumn(
    #"Personalizada agregada17",
    "DetalleFinal",
    each
        let
            HorasNormalesSafe = try Number.From([HorasNormales]) otherwise 0,
            HorasExtraSafe = try Number.From([HorasExtra]) otherwise 0,
            FechaTramo = try Date.From([TablaAcumulada.InicioTramo]) otherwise null,
            HoraTramo = try Time.From([TablaAcumulada.InicioTramo]) otherwise null,
            EsFinSemana = if FechaTramo = null then false else Date.DayOfWeek(FechaTramo, Day.Monday) >= 5,
            EsHorarioNocturno = if HoraTramo = null then false else (HoraTramo >= #time(22,0,0) or HoraTramo < #time(6,0,0)),

            // Criterios especiales del tramo base
            CriteriosBase = (if EsFinSemana then 1 else 0) + (if EsHorarioNocturno then 1 else 0),

            // Tipo para la parte normal
            TipoNormal =
                if CriteriosBase >= 2 then "EXTRA ESPECIAL"
                else if CriteriosBase = 1 then "NOCTURNA"
                else "ORDINARIA",

            // Tipo para la parte extra
            TipoExtra =
                if (CriteriosBase + 1) >= 2 then "EXTRA ESPECIAL"
                else "EXTRA ORDINARIA"
        in
            List.RemoveNulls({
                if HorasNormalesSafe > 0 then
                    [HorasFinal = HorasNormalesSafe, TipoFinal = TipoNormal]
                else
                    null,

                if HorasExtraSafe > 0 then
                    [HorasFinal = HorasExtraSafe, TipoFinal = TipoExtra]
                else
                    null
            }),
    type list
),
    #"Se expandió DetalleFinal" = Table.ExpandListColumn(#"Personalizada agregada18", "DetalleFinal"),
    #"Se expandió DetalleFinal1" = Table.ExpandRecordColumn(#"Se expandió DetalleFinal", "DetalleFinal", {"HorasFinal", "TipoFinal"}, {"DetalleFinal.HorasFinal", "DetalleFinal.TipoFinal"}),
    #"Filas filtradas" = Table.SelectRows(#"Se expandió DetalleFinal1", each [DetalleFinal.HorasFinal] <> null and [DetalleFinal.HorasFinal] <> ""),
    #"Columnas con nombre cambiado3" = Table.RenameColumns(#"Filas filtradas",{{"TablaAcumulada.Hora entrada", "Hora entrada"}, {"TablaAcumulada.Cliente", "Cliente"}, {"TablaAcumulada.Tipo de parte", "Tipo de parte"}, {"TablaAcumulada.Hora salida", "Hora salida"}, {"TablaAcumulada.Trabajador", "Trabajador"}, {"TablaAcumulada.Horas", "Horas"}, {"TablaAcumulada.FechaBase", "FechaBase"}, {"TablaAcumulada.TipoHora", "Tipo Hora"}, {"DetalleFinal.HorasFinal", "Horas Final"}, {"DetalleFinal.TipoFinal", "Tipo Final"}, {"TablaAcumulada.Categoría_Trabajador", "Categoría_Trabajador"}, {"TablaAcumulada.Sección", "Sección"}, {"TablaAcumulada.Id", "Id"}}),
    #"Tipo cambiado1" = Table.TransformColumnTypes(#"Columnas con nombre cambiado3",{
{"Hora entrada", type datetime},
        {"Hora salida", type datetime},
        {"FechaBase", type datetime},
        {"TablaAcumulada.InicioTramo", type datetime},
        {"TablaAcumulada.FinTramo", type datetime},
        {"TablaAcumulada.Nºpernoctaciones", Int64.Type}
}),
    #"Personalizada agregada19" = Table.AddColumn(#"Tipo cambiado1", "Tipo_Hora_final", each let
    HorasAntes = [HorasAcumuladas] - [TablaAcumulada.HorasTramo],
    Limite = 8
in
    if [HorasAcumuladas] <= Limite then
        #table(
            {"Inicio","Fin","Horas","Tipo"},
            {
                {[TablaAcumulada.InicioTramo], [TablaAcumulada.FinTramo], [TablaAcumulada.HorasTramo], [#"Tipo Hora"]}
            }
        )
    else if HorasAntes >= Limite then
        #table(
            {"Inicio","Fin","Horas","Tipo"},
            {
                {[TablaAcumulada.InicioTramo], [TablaAcumulada.FinTramo], [TablaAcumulada.HorasTramo], "EXTRA ESPECIAL"}
            }
        )
    else
        let
            ParteNormal = Limite - HorasAntes,
            ParteExtra = [TablaAcumulada.HorasTramo] - ParteNormal,

            PuntoCorte = [TablaAcumulada.InicioTramo] + #duration(0, ParteNormal, 0, 0)
        in
            #table(
                {"Inicio","Fin","Horas","Tipo"},
                {
                    {[TablaAcumulada.InicioTramo], PuntoCorte, ParteNormal, [#"Tipo Hora"]},
                    {PuntoCorte, [TablaAcumulada.FinTramo], ParteExtra, "EXTRA ESPECIAL"}
                }
            )),
    #"Columnas quitadas1" = Table.RemoveColumns(#"Personalizada agregada19",{"Tipo_Hora_final", "TablaAcumulada.OData_¿Haspernoctado?"}),
    #"Columnas reordenadas" = Table.ReorderColumns(#"Columnas quitadas1",{"Id", "TablaIndexada", "TablaIndexada.1", "TablaAcumulada.Title", "Tipo de parte", "Cliente", "Hora entrada", "Hora salida", "TablaAcumulada.Horasdedesplazamiento(iday", "TablaAcumulada.KM(sihayvehículoprop", "TablaAcumulada.Nºpernoctaciones", "TablaAcumulada.Descripcióntrabajos", "TablaAcumulada.Nºpresupuesto", "TablaAcumulada.ID.1", "Trabajador", "Horas", "FechaBase", "TablaAcumulada.InicioTramo", "TablaAcumulada.FinTramo", "TablaAcumulada.HorasTramo", "Tipo Hora", "TablaAcumulada.Orden", "TablaAcumulada.HorasAcumuladas", "TablaAcumulada.Categoría", "Categoría_Trabajador", "HorasAntes", "HorasNormales", "HorasExtra", "TipoHoraFinal", "Key", "Horas Final", "Tipo Final"}),
    #"Personalizada agregada20" = Table.AddColumn(#"Columnas reordenadas", "Key_nomina", each [#"TablaAcumulada.Categoría"] & "|" & [Tipo Final]),
    #"Personalizada agregada21" = Table.AddColumn(#"Personalizada agregada20", "Key_variable", each [Categoría_Trabajador] & "|" & [#"Tipo Final"]),
    #"Columnas quitadas2" = Table.RemoveColumns(#"Personalizada agregada21",{"TablaIndexada.1", "TablaAcumulada.Title", "TablaIndexada"}),
    #"Columnas con nombre cambiado4" = Table.RenameColumns(#"Columnas quitadas2",{{"TablaAcumulada.Categoría", "Categoría_nómina"}, {"Categoría_Trabajador", "Categoría_facturación"}, {"TablaAcumulada.Horasdedesplazamiento(iday", "Horas Desplazamiento"}, {"TablaAcumulada.KM(sihayvehículoprop", "KM (Si hay vehículo propio)"}, {"TablaAcumulada.Nºpernoctaciones", "Nº Pernoctaciones"}, {"TablaAcumulada.Descripcióntrabajos", "Descripción trabajos"}, {"TablaAcumulada.Nºpresupuesto", "Nº Presupuesto"}}),
    #"Columnas reordenadas1" = Table.ReorderColumns(#"Columnas con nombre cambiado4",{"Id", "Tipo de parte", "Cliente", "Hora entrada", "Hora salida", "Horas Desplazamiento", "KM (Si hay vehículo propio)", "Nº Pernoctaciones", "Descripción trabajos", "Nº Presupuesto", "Trabajador", "Horas", "FechaBase", "Jornada", "TablaAcumulada.InicioTramo", "TablaAcumulada.FinTramo", "TablaAcumulada.HorasTramo", "Tipo Hora", "TablaAcumulada.Orden", "TablaAcumulada.HorasAcumuladas", "Sección", "Tipo Final", "Categoría_facturación", "Categoría_nómina", "Horas Final", "HorasAntes", "HorasNormales", "HorasExtra", "TipoHoraFinal", "Key", "Key_nomina", "Key_variable", "TablaAcumulada.ID.1"})
in
    #"Columnas reordenadas1"
;
