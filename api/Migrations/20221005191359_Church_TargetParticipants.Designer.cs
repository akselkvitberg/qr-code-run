﻿// <auto-generated />
using System;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;
using api.Data;

#nullable disable

namespace api.Migrations
{
    [DbContext(typeof(DataContext))]
    [Migration("20221005191359_Church_TargetParticipants")]
    partial class Church_TargetParticipants
    {
        protected override void BuildTargetModel(ModelBuilder modelBuilder)
        {
#pragma warning disable 612, 618
            modelBuilder
                .HasAnnotation("ProductVersion", "6.0.9")
                .HasAnnotation("Relational:MaxIdentifierLength", 63);

            NpgsqlModelBuilderExtensions.UseIdentityByDefaultColumns(modelBuilder);

            modelBuilder.Entity("api.Data.CacheEntry", b =>
                {
                    b.Property<string>("Key")
                        .HasColumnType("text");

                    b.Property<DateTimeOffset?>("Expires")
                        .HasColumnType("timestamp with time zone");

                    b.Property<string>("Value")
                        .IsRequired()
                        .HasColumnType("text");

                    b.HasKey("Key");

                    b.ToTable("CacheEntries");
                });

            modelBuilder.Entity("api.Data.Church", b =>
                {
                    b.Property<string>("Name")
                        .HasColumnType("text");

                    b.Property<string>("CountryCode")
                        .IsRequired()
                        .HasColumnType("text");

                    b.Property<int>("Participants")
                        .HasColumnType("integer");

                    b.Property<int>("TargetParticipants")
                        .HasColumnType("integer");

                    b.HasKey("Name");

                    b.ToTable("Churches");
                });

            modelBuilder.Entity("api.Repositories.FunFact", b =>
                {
                    b.Property<int>("FunFactId")
                        .ValueGeneratedOnAdd()
                        .HasColumnType("integer");

                    NpgsqlPropertyBuilderExtensions.UseIdentityByDefaultColumn(b.Property<int>("FunFactId"));

                    b.Property<string>("Content")
                        .IsRequired()
                        .HasColumnType("text");

                    b.Property<string>("Title")
                        .IsRequired()
                        .HasColumnType("text");

                    b.HasKey("FunFactId");

                    b.ToTable("FunFact");
                });

            modelBuilder.Entity("api.Repositories.QrCode", b =>
                {
                    b.Property<int>("QrCodeId")
                        .HasColumnType("integer");

                    b.Property<int>("FunFactId")
                        .HasColumnType("integer");

                    b.Property<int>("GroupId")
                        .HasColumnType("integer");

                    b.Property<bool>("IsSecret")
                        .HasColumnType("boolean");

                    b.Property<int>("Points")
                        .HasColumnType("integer");

                    b.HasKey("QrCodeId");

                    b.HasIndex("FunFactId");

                    b.ToTable("QrCodes");
                });

            modelBuilder.Entity("api.Repositories.Score", b =>
                {
                    b.Property<int>("TeamId")
                        .HasColumnType("integer");

                    b.Property<int>("Id")
                        .HasColumnType("integer");

                    b.Property<bool>("IsSecret")
                        .HasColumnType("boolean");

                    b.Property<int>("Points")
                        .HasColumnType("integer");

                    b.HasKey("TeamId", "Id");

                    b.ToTable("Score");
                });

            modelBuilder.Entity("api.Repositories.Team", b =>
                {
                    b.Property<int>("Id")
                        .ValueGeneratedOnAdd()
                        .HasColumnType("integer");

                    NpgsqlPropertyBuilderExtensions.UseIdentityByDefaultColumn(b.Property<int>("Id"));

                    b.Property<string>("ChurchName")
                        .IsRequired()
                        .HasColumnType("text");

                    b.Property<DateTime?>("FirstScannedQrCode")
                        .HasColumnType("timestamp with time zone");

                    b.Property<DateTime?>("LastScannedQrCode")
                        .HasColumnType("timestamp with time zone");

                    b.Property<int>("Members")
                        .HasColumnType("integer");

                    b.Property<string>("TeamName")
                        .IsRequired()
                        .HasColumnType("text");

                    b.HasKey("Id");

                    b.ToTable("Teams");
                });

            modelBuilder.Entity("api.Repositories.QrCode", b =>
                {
                    b.HasOne("api.Repositories.FunFact", "FunFact")
                        .WithMany()
                        .HasForeignKey("FunFactId")
                        .OnDelete(DeleteBehavior.Cascade)
                        .IsRequired();

                    b.Navigation("FunFact");
                });

            modelBuilder.Entity("api.Repositories.Score", b =>
                {
                    b.HasOne("api.Repositories.Team", "Team")
                        .WithMany("QrCodesScanned")
                        .HasForeignKey("TeamId")
                        .OnDelete(DeleteBehavior.Cascade)
                        .IsRequired();

                    b.Navigation("Team");
                });

            modelBuilder.Entity("api.Repositories.Team", b =>
                {
                    b.Navigation("QrCodesScanned");
                });
#pragma warning restore 612, 618
        }
    }
}
